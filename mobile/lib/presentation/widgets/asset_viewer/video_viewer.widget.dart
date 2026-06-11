import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/setting.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/setting.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/infrastructure/repositories/storage.repository.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/airplay_timeline_playback.helper.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/is_motion_video_playing.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/video_player_provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/providers/airplay.provider.dart';
import 'package:immich_mobile/services/airplay.service.dart';
import 'package:immich_mobile/widgets/asset_viewer/airplay_loader.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/setting.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:logging/logging.dart';
import 'package:native_video_player/native_video_player.dart';

class NativeVideoViewer extends ConsumerStatefulWidget {
  final BaseAsset asset;
  final bool isCurrent;
  final bool showControls;
  final Widget image;

  const NativeVideoViewer({
    super.key,
    required this.asset,
    required this.image,
    this.isCurrent = false,
    this.showControls = true,
  });

  @override
  ConsumerState<NativeVideoViewer> createState() => _NativeVideoViewerState();
}

class _NativeVideoViewerState extends ConsumerState<NativeVideoViewer> with WidgetsBindingObserver {
  static final _log = Logger('NativeVideoViewer');

  NativeVideoPlayerController? _controller;
  Future<VideoSource?>? _videoSourceFuture;
  int _sourceEpoch = 0;
  Timer? _loadTimer;
  bool _isVideoReady = false;
  bool _shouldPlayOnForeground = true;
  bool _isAirPlayActive = false;
  bool _isPreparingAirPlay = false;
  bool _isSourceReady = false;

  VideoPlayerNotifier get _notifier => ref.read(videoPlayerProvider(widget.asset.heroTag).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isAirPlayActive = ref.read(airplayProvider);
    _reloadVideoSource(_isAirPlayActive);
  }

  @override
  void didUpdateWidget(NativeVideoViewer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isCurrent == oldWidget.isCurrent || _controller == null) return;

    if (!widget.isCurrent) {
      _loadTimer?.cancel();
      _notifier.pause();
      return;
    }

    // Prevent unnecessary loading when swiping between assets.
    _loadTimer = Timer(const Duration(milliseconds: 200), _loadVideo);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _loadTimer?.cancel();
    _removeListeners();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_shouldPlayOnForeground) await _notifier.play();
      case AppLifecycleState.paused:
        _shouldPlayOnForeground = await _controller?.isPlaying() ?? true;
        if (_shouldPlayOnForeground) await _notifier.pause();
      default:
    }
  }

  void _reloadVideoSource(bool airPlayActive) {
    final epoch = ++_sourceEpoch;

    if (AirplayTimelinePlayback.needsSourcePreparation(isAirPlayActive: airPlayActive, asset: widget.asset)) {
      setState(() {
        _isPreparingAirPlay = true;
        _isSourceReady = false;
        _isVideoReady = false;
      });
      _detachController();
    }

    _videoSourceFuture = _createSource(airPlayActive);
    unawaited(_applyResolvedSource(airPlayActive, epoch));
  }

  void _onAirPlayChanged(bool airPlayActive) {
    if (_isAirPlayActive == airPlayActive) {
      return;
    }

    _isAirPlayActive = airPlayActive;
    _reloadVideoSource(airPlayActive);
  }

  void _detachController() {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    _removeListeners();
    try {
      controller.stop();
    } catch (_) {}
    _controller = null;
  }

  Future<void> _applyResolvedSource(bool airPlayActive, int epoch) async {
    final source = await _videoSourceFuture;
    if (!mounted || epoch != _sourceEpoch || source == null) {
      return;
    }

    setState(() {
      _isSourceReady = true;
      _isPreparingAirPlay = false;
    });

    final controller = _controller;
    if (controller == null || !widget.isCurrent) {
      return;
    }

    await _notifier.load(source);
    final loopVideo = ref.read(appSettingsServiceProvider).getSetting<bool>(AppSettingsEnum.loopVideo);
    await _notifier.setLoop(!widget.asset.isMotionPhoto && loopVideo);
    await _notifier.setVolume(1);

    if (airPlayActive && widget.asset.isVideo) {
      await _notifier.play();
    }
  }

  Future<VideoSource?> _createSource(bool airPlayActive) async {
    if (!mounted) return null;

    final videoAsset = await ref.read(assetServiceProvider).getAsset(widget.asset) ?? widget.asset;
    if (!mounted) return null;

    try {
      if (videoAsset.hasLocal && videoAsset.livePhotoVideoId == null && videoAsset.isVideo) {
        final id = videoAsset is LocalAsset ? videoAsset.id : (videoAsset as RemoteAsset).localId!;
        final file = await StorageRepository().getFileForAsset(id);
        if (!mounted) return null;

        if (file == null) {
          throw Exception('No file found for the video');
        }

        // Pass a file:// URI so Android's Uri.parse doesn't
        // interpret characters like '#' as fragment identifiers.
        return VideoSource.init(
          path: CurrentPlatform.isAndroid ? file.uri.toString() : file.path,
          type: VideoSourceType.file,
        );
      }

      final localPath = await AirplayService.resolveTimelineLocalPlaybackPath(
        videoAsset,
        ref,
        airPlayActive: airPlayActive,
      );
      if (localPath != null) {
        return VideoSource.init(path: localPath, type: VideoSourceType.file);
      }

      if (airPlayActive &&
          videoAsset.isImage &&
          !videoAsset.isMotionPhoto &&
          AirplayTimelinePlayback.isSupported) {
        ref.read(airplayProvider.notifier).disableAirPlayMode();
      }

      if (videoAsset is! RemoteAsset) {
        _log.warning('Cannot create remote video source for non-remote asset ${videoAsset.name}');
        return null;
      }

      final remoteId = videoAsset.id;

      final serverEndpoint = Store.get(StoreKey.serverEndpoint);
      final isOriginalVideo = ref.read(settingsProvider).get<bool>(Setting.loadOriginalVideo);
      final String postfixUrl = isOriginalVideo ? 'original' : 'video/playback';
      final String videoUrl = videoAsset.livePhotoVideoId != null
          ? '$serverEndpoint/assets/${videoAsset.livePhotoVideoId}/$postfixUrl'
          : '$serverEndpoint/assets/$remoteId/$postfixUrl';

      return VideoSource.init(path: videoUrl, type: VideoSourceType.network, headers: ApiService.getRequestHeaders());
    } catch (error) {
      _log.severe('Error creating video source for asset ${videoAsset.name}: $error');
      return null;
    }
  }

  void _onPlaybackReady() async {
    if (!mounted || !widget.isCurrent) return;

    _notifier.onNativePlaybackReady();

    // onPlaybackReady may be called multiple times, usually when more data
    // loads. If this is not the first time that the player has become ready, we
    // should not autoplay.
    if (_isVideoReady) return;

    setState(() {
      _isVideoReady = true;
      _isSourceReady = true;
      _isPreparingAirPlay = false;
    });

    if (ref.read(assetViewerProvider).showingDetails) return;

    final autoPlayVideo = AppSetting.get(Setting.autoPlayVideo);
    if (autoPlayVideo) await _notifier.play();

    // AirPlay photos are converted to a short video; pause to keep a static frame.
    if (_isAirPlayActive && widget.asset.isImage && !widget.asset.isMotionPhoto) {
      Timer(const Duration(milliseconds: 500), () async {
        if (!mounted) return;
        try {
          await _controller?.pause();
        } catch (_) {}
      });
    }
  }

  void _onPlaybackEnded() {
    if (!mounted) return;

    _notifier.onNativePlaybackEnded();

    if (_controller?.playbackInfo?.status == PlaybackStatus.stopped) {
      ref.read(isPlayingMotionVideoProvider.notifier).playing = false;
    }
  }

  void _onPlaybackPositionChanged() {
    if (!mounted) return;
    _notifier.onNativePositionChanged();
  }

  void _onPlaybackStatusChanged() {
    if (!mounted) return;
    _notifier.onNativeStatusChanged();
  }

  void _removeListeners() {
    _controller?.onPlaybackPositionChanged.removeListener(_onPlaybackPositionChanged);
    _controller?.onPlaybackStatusChanged.removeListener(_onPlaybackStatusChanged);
    _controller?.onPlaybackReady.removeListener(_onPlaybackReady);
    _controller?.onPlaybackEnded.removeListener(_onPlaybackEnded);
  }

  void _loadVideo() async {
    final nc = _controller;
    if (nc == null || nc.videoSource != null || !mounted) return;

    final source = await _videoSourceFuture;
    if (source == null || !mounted) return;

    await _notifier.load(source);
    final loopVideo = ref.read(appSettingsServiceProvider).getSetting<bool>(AppSettingsEnum.loopVideo);
    await _notifier.setLoop(!widget.asset.isMotionPhoto && loopVideo);
    await _notifier.setVolume(1);
  }

  void _initController(NativeVideoPlayerController nc) {
    if (_controller != null || !mounted) return;

    _notifier.attachController(nc);

    nc.onPlaybackPositionChanged.addListener(_onPlaybackPositionChanged);
    nc.onPlaybackStatusChanged.addListener(_onPlaybackStatusChanged);
    nc.onPlaybackReady.addListener(_onPlaybackReady);
    nc.onPlaybackEnded.addListener(_onPlaybackEnded);

    _controller = nc;

    if (widget.isCurrent) _loadVideo();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(airplayProvider, (previous, next) {
      if (previous != next) {
        _onAirPlayChanged(next);
      }
    });

    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));
    final status = ref.watch(videoPlayerProvider(widget.asset.heroTag).select((v) => v.status));
    final isAirPlayActive = ref.watch(airplayProvider);
    final showAirPlayOverlay =
        AirplayTimelinePlayback.isSupported && isAirPlayActive && (!_isSourceReady || _isPreparingAirPlay);
    final showPlayer =
        !isCasting && widget.isCurrent && (!isAirPlayActive || _isSourceReady) && (!isAirPlayActive || !_isPreparingAirPlay);

    return IgnorePointer(
      child: Stack(
        children: [
          Center(child: widget.image),
          if (showPlayer)
            Visibility.maintain(
              visible: _isVideoReady,
              child: NativeVideoPlayerView(
                key: ValueKey('${widget.asset.heroTag}_${isAirPlayActive ? 'airplay' : 'direct'}'),
                onViewReady: _initController,
              ),
            ),
          if (!isCasting)
            Center(
              child: AnimatedOpacity(
                opacity: status == VideoPlaybackStatus.buffering ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: const CircularProgressIndicator(),
              ),
            ),
          if (showAirPlayOverlay)
            const Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: Color(0x42000000),
                  child: AirplayLoader(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
