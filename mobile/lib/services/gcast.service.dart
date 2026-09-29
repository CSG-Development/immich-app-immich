import 'dart:async';

import 'package:cast/session.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/models/cast/cast_manager_state.dart';
import 'package:immich_mobile/models/sessions/session_create_response.model.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/gcast.repository.dart';
import 'package:immich_mobile/repositories/sessions_api.repository.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
// ignore: import_rule_openapi, we are only using the AssetMediaSize enum
import 'package:openapi/api.dart';

final gCastServiceProvider = Provider(
  (ref) => GCastService(
    ref.watch(gCastRepositoryProvider),
    ref.watch(sessionsAPIRepositoryProvider),
    ref.watch(assetApiRepositoryProvider),
  ),
);

class GCastService {
  final GCastRepository _gCastRepository;
  final SessionsAPIRepository _sessionsApiService;
  final AssetApiRepository _assetApiRepository;

  SessionCreateResponse? sessionKey;
  String? currentAssetId;
  bool isConnected = false;
  int? _sessionId;
  Timer? _mediaStatusPollingTimer;

  void Function(bool)? onConnectionState;

  void Function(Duration)? onCurrentTime;

  void Function(Duration)? onDuration;

  void Function(String)? onReceiverName;

  void Function(CastState)? onCastState;

  void Function(String)? onCastError;

  /// A load request that was queued because the media receiver application
  /// had not registered its transport yet. Flushed on the next
  /// RECEIVER_STATUS that shows the application running.
  (RemoteAsset, String, String)? _pendingLoad;
  Timer? _pendingLoadTimer;

  GCastService(this._gCastRepository, this._sessionsApiService, this._assetApiRepository) {
    _gCastRepository.onCastStatus = _onCastStatusCallback;
    _gCastRepository.onCastMessage = _onCastMessageCallback;
  }

  void _onCastStatusCallback(CastSessionState state) {
    if (state == CastSessionState.connected) {
      onConnectionState?.call(true);
      isConnected = true;
    } else if (state == CastSessionState.closed) {
      onConnectionState?.call(false);
      isConnected = false;
      onReceiverName?.call("");
      currentAssetId = null;
    }
  }

  void _onCastMessageCallback(Map<String, dynamic> message) {
    switch (message['type']) {
      case "MEDIA_STATUS":
        _handleMediaStatus(message);
        break;
      case "LOAD_FAILED":
        // The receiver could not fetch/decode the content URL (network, TLS,
        // auth or codec). Surface it instead of leaving the user staring at
        // the idle placeholder screen.
        _pendingLoad = null;
        _pendingLoadTimer?.cancel();
        _mediaStatusPollingTimer?.cancel();
        onCastState?.call(CastState.idle);
        onCastError?.call(
          "The cast device could not load the media. Make sure the Immich server "
          "is reachable from the device and that its certificate is trusted.",
        );
        break;
      case "RECEIVER_STATUS":
        _flushPendingLoad(message);
        break;
    }
  }

  void _flushPendingLoad(Map<String, dynamic> message) {
    final pending = _pendingLoad;
    if (pending == null) {
      return;
    }

    final applications = (message["status"] as Map<String, dynamic>?)?["applications"];
    // Media namespace messages are only delivered once the media receiver
    // application is running. Latest load wins.
    if (applications is! List || applications.isEmpty) {
      return;
    }

    _pendingLoad = null;
    _pendingLoadTimer?.cancel();
    _sendLoad(pending.$1, pending.$2, pending.$3);
  }

  void _handleMediaStatus(Map<String, dynamic> message) {
    final statusList = (message['status'] as List).whereType<Map<String, dynamic>>().toList();

    if (statusList.isEmpty) {
      return;
    }

    final status = statusList[0];
    switch (status['playerState']) {
      case "PLAYING":
        onCastState?.call(CastState.playing);
        break;
      case "PAUSED":
        onCastState?.call(CastState.paused);
        break;
      case "BUFFERING":
        onCastState?.call(CastState.buffering);
        break;
      case "IDLE":
        onCastState?.call(CastState.idle);

        // stop polling for media status if the video finished playing
        if (status["idleReason"] == "FINISHED") {
          _mediaStatusPollingTimer?.cancel();
        }

        break;
    }

    if (status["media"] != null && status["media"]["duration"] != null) {
      final duration = Duration(milliseconds: (status["media"]["duration"] * 1000 ?? 0).toInt());
      onDuration?.call(duration);
    }

    if (status["mediaSessionId"] != null) {
      _sessionId = status["mediaSessionId"];
    }

    if (status["currentTime"] != null) {
      final currentTime = Duration(milliseconds: (status["currentTime"] * 1000 ?? 0).toInt());
      onCurrentTime?.call(currentTime);
    }
  }

  Future<void> connect(dynamic device) async {
    await _gCastRepository.connect(device);

    onReceiverName?.call(device.extras["fn"] ?? "Google Cast");
  }

  CastDestinationType getType() {
    return CastDestinationType.googleCast;
  }

  Future<bool> initialize() async {
    // there is nothing blocking us from using Google Cast that we can check for
    return true;
  }

  Future<void> disconnect() async {
    onReceiverName?.call("");
    _pendingLoad = null;
    _pendingLoadTimer?.cancel();
    currentAssetId = null;
    await _gCastRepository.disconnect();
  }

  bool isSessionValid() {
    // check if we already have a session token
    // we should always have a expiration date
    if (sessionKey == null || sessionKey?.expiresAt == null) {
      return false;
    }

    final tokenExpiration = DateTime.parse(sessionKey!.expiresAt!);

    // we want to make sure we have at least 10 seconds remaining in the session
    // this is to account for network latency and other delays when sending the request
    final bufferedExpiration = tokenExpiration.subtract(const Duration(seconds: 10));

    return bufferedExpiration.isAfter(DateTime.now());
  }

  Future<void> loadMedia(RemoteAsset asset, bool reload) async {
    if (!isConnected) {
      return;
    } else if (asset.id == currentAssetId && !reload) {
      return;
    }

    try {
      // create a session key
      if (!isSessionValid()) {
        sessionKey = await _sessionsApiService.createSession(
          "Cast",
          "Google Cast",
          duration: const Duration(minutes: 15).inSeconds,
        );
      }

      final unauthenticatedUrl = asset.isVideo
          ? getPlaybackUrlForRemoteId(asset.id)
          : getThumbnailUrlForRemoteId(asset.id, type: AssetMediaSize.fullsize);

      final authenticatedURL = _withSessionKey(unauthenticatedUrl, sessionKey?.token);

      // get image mime type
      final mimeType = await _assetApiRepository.getAssetMIMEType(asset.id);

      if (mimeType == null) {
        onCastError?.call("Unable to determine the media type of the asset.");
        return;
      }

      currentAssetId = asset.id;

      // The media receiver application registers its transport asynchronously
      // after we connect. If it is not registered yet, queue the load and let
      // the next RECEIVER_STATUS flush it instead of losing the message.
      if (_gCastRepository.getSessionId() == null) {
        _pendingLoad = (asset, authenticatedURL, mimeType);
        _pendingLoadTimer?.cancel();
        _pendingLoadTimer = Timer(const Duration(seconds: 10), () {
          // The media receiver application never became ready; report it
          // instead of leaving the user on the idle placeholder screen.
          _pendingLoad = null;
          onCastError?.call("The cast device did not become ready in time. Try connecting again.");
        });
        return;
      }

      _sendLoad(asset, authenticatedURL, mimeType);
    } catch (e) {
      onCastError?.call("Failed to start casting: $e");
    }
  }

  String _withSessionKey(String url, String? token) {
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}sessionKey=$token';
  }

  void _sendLoad(RemoteAsset asset, String url, String mimeType) {
    _gCastRepository.sendMessage(CastSession.kNamespaceMedia, {
      "type": "LOAD",
      "media": {
        "contentId": url,
        "streamType": "BUFFERED",
        "contentType": mimeType,
        "contentUrl": url,
      },
      "autoplay": true,
    });

    // we need to poll for media status since the cast device does not
    // send a message when the media is loaded for whatever reason
    // only do this on videos
    _mediaStatusPollingTimer?.cancel();

    if (asset.isVideo) {
      _mediaStatusPollingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (isConnected) {
          _gCastRepository.sendMessage(CastSession.kNamespaceMedia, {
            "type": "GET_STATUS",
            "mediaSessionId": _sessionId,
          });
        } else {
          timer.cancel();
        }
      });
    }
  }

  void play() {
    _gCastRepository.sendMessage(CastSession.kNamespaceMedia, {"type": "PLAY", "mediaSessionId": _sessionId});
  }

  void pause() {
    _gCastRepository.sendMessage(CastSession.kNamespaceMedia, {"type": "PAUSE", "mediaSessionId": _sessionId});
  }

  void seekTo(Duration position) {
    _gCastRepository.sendMessage(CastSession.kNamespaceMedia, {
      "type": "SEEK",
      "mediaSessionId": _sessionId,
      "currentTime": position.inSeconds,
    });
  }

  void stop() {
    _gCastRepository.sendMessage(CastSession.kNamespaceMedia, {"type": "STOP", "mediaSessionId": _sessionId});
    _mediaStatusPollingTimer?.cancel();

    _pendingLoad = null;
    _pendingLoadTimer?.cancel();
    currentAssetId = null;
  }

  // 0x01 is display capability bitmask
  bool isDisplay(int ca) => (ca & 0x01) != 0;

  Future<List<(String, CastDestinationType, dynamic)>> getDevices() async {
    final dests = await _gCastRepository.listDestinations();

    return dests
        .map((device) => (device.extras["fn"] ?? "Google Cast", CastDestinationType.googleCast, device))
        .where((device) {
          final caString = device.$3.extras["ca"];
          final caNumber = int.tryParse(caString ?? "0") ?? 0;

          return isDisplay(caNumber);
        })
        .toList(growable: false);
  }
}
