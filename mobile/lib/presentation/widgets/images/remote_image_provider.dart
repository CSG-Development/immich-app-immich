import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/infrastructure/loaders/image_request.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/presentation/widgets/images/animated_image_stream_completer.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/presentation/widgets/images/one_frame_multi_image_stream_completer.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:openapi/api.dart';

class RemoteImageProvider extends CancellableImageProvider<RemoteImageProvider>
    with CancellableImageProviderMixin<RemoteImageProvider> {
  /// Absolute URL for one-off remote images (faces, album covers, etc.).
  final String? _fixedUrl;

  /// When set, the thumbnail URL is resolved at load time from [StoreKey.serverEndpoint]
  /// so endpoint switches (local ↔ remote) do not keep a stale host.
  final String? assetId;
  final String? thumbhash;
  final bool edited;

  RemoteImageProvider({required String url, this.edited = true}) : _fixedUrl = url, assetId = null, thumbhash = null;

  RemoteImageProvider.thumbnail({required String assetId, required String thumbhash, this.edited = true})
    : assetId = assetId,
      thumbhash = thumbhash,
      _fixedUrl = null;

  String get url => _fixedUrl ?? getThumbnailUrlForRemoteId(assetId!, thumbhash: thumbhash, edited: edited);

  @override
  Future<RemoteImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(RemoteImageProvider key, ImageDecoderCallback decode) {
    return OneFramePlaceholderImageStreamCompleter(
      _codec(key, decode),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('URL', key.url),
      ],
      onLastListenerRemoved: cancel,
    );
  }

  Stream<ImageInfo> _codec(RemoteImageProvider key, ImageDecoderCallback decode) {
    final request = this.request = RemoteImageRequest(uri: key.url, headers: ApiService.getRequestHeaders());
    return loadRequest(request, decode, isFinal: true);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! RemoteImageProvider) {
      return false;
    }
    if (edited != other.edited) {
      return false;
    }
    if (assetId != null || other.assetId != null) {
      return assetId == other.assetId && thumbhash == other.thumbhash;
    }
    return _fixedUrl == other._fixedUrl;
  }

  @override
  int get hashCode => assetId != null ? Object.hash(assetId, thumbhash, edited) : Object.hash(_fixedUrl, edited);
}

class RemoteFullImageProvider extends CancellableImageProvider<RemoteFullImageProvider>
    with CancellableImageProviderMixin<RemoteFullImageProvider> {
  final String assetId;
  final String thumbhash;
  final AssetType assetType;
  final bool isAnimated;
  final bool edited;

  RemoteFullImageProvider({
    required this.assetId,
    required this.thumbhash,
    required this.assetType,
    required this.isAnimated,
    this.edited = true,
  });

  @override
  Future<RemoteFullImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(RemoteFullImageProvider key, ImageDecoderCallback decode) {
    if (key.isAnimated) {
      return AnimatedImageStreamCompleter(
        stream: _animatedCodec(key, decode),
        scale: 1.0,
        initialImage: getInitialImage(
          RemoteImageProvider.thumbnail(assetId: key.assetId, thumbhash: key.thumbhash, edited: key.edited),
        ),
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<ImageProvider>('Image provider', this),
          DiagnosticsProperty<String>('Asset Id', key.assetId),
          DiagnosticsProperty<bool>('isAnimated', key.isAnimated),
        ],
        onLastListenerRemoved: cancel,
      );
    }

    return OneFramePlaceholderImageStreamCompleter(
      _codec(key, decode),
      initialImage: getInitialImage(
        RemoteImageProvider.thumbnail(assetId: key.assetId, thumbhash: key.thumbhash, edited: key.edited),
      ),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Asset Id', key.assetId),
        DiagnosticsProperty<bool>('isAnimated', key.isAnimated),
      ],
      onLastListenerRemoved: cancel,
    );
  }

  Stream<ImageInfo> _codec(RemoteFullImageProvider key, ImageDecoderCallback decode) async* {
    yield* initialImageStream();

    if (isCancelled) {
      return;
    }

    final previewRequest = request = RemoteImageRequest(
      uri: getThumbnailUrlForRemoteId(
        key.assetId,
        type: AssetMediaSize.preview,
        thumbhash: key.thumbhash,
        edited: key.edited,
      ),
      headers: ApiService.getRequestHeaders(),
    );
    final loadOriginal = assetType == AssetType.image && SettingsRepository.instance.appConfig.image.loadOriginal;
    yield* loadRequest(previewRequest, decode, isFinal: !loadOriginal);

    if (!loadOriginal) {
      return;
    }

    if (isCancelled) {
      return;
    }

    final originalRequest = request = RemoteImageRequest(
      uri: getOriginalUrlForRemoteId(key.assetId, edited: key.edited),
      headers: ApiService.getRequestHeaders(),
    );
    yield* loadRequest(originalRequest, decode, isFinal: true);
  }

  Stream<Object> _animatedCodec(RemoteFullImageProvider key, ImageDecoderCallback decode) async* {
    yield* initialImageStream();

    if (isCancelled) {
      return;
    }

    final previewRequest = request = RemoteImageRequest(
      uri: getThumbnailUrlForRemoteId(
        key.assetId,
        type: AssetMediaSize.preview,
        thumbhash: key.thumbhash,
        edited: key.edited,
      ),
      headers: ApiService.getRequestHeaders(),
    );
    yield* loadRequest(previewRequest, decode, isFinal: false);

    if (isCancelled) {
      return;
    }

    // always try original for animated, since previews don't support animation
    final originalRequest = request = RemoteImageRequest(
      uri: getOriginalUrlForRemoteId(key.assetId, edited: key.edited),
      headers: ApiService.getRequestHeaders(),
    );
    final codec = await loadCodecRequest(originalRequest, isFinal: true);
    if (codec == null) {
      if (isCancelled) {
        return;
      }
      throw StateError('Failed to load animated codec for asset ${key.assetId}');
    }
    yield codec;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is RemoteFullImageProvider) {
      return assetId == other.assetId &&
          thumbhash == other.thumbhash &&
          isAnimated == other.isAnimated &&
          edited == other.edited;
    }

    return false;
  }

  @override
  int get hashCode => assetId.hashCode ^ thumbhash.hashCode ^ isAnimated.hashCode ^ edited.hashCode;
}

/// Remote image provider that always loads the original image file only.
///
/// Unlike [RemoteFullImageProvider], this provider does **not** stream the
/// preview-sized image first. It directly requests the original asset URL.
/// This is intended for use cases like image editing where we must operate
/// on the full‑resolution source.
class RemoteOriginalImageProvider extends CancellableImageProvider<RemoteOriginalImageProvider>
    with CancellableImageProviderMixin<RemoteOriginalImageProvider> {
  final String assetId;
  final bool edited;

  RemoteOriginalImageProvider({required this.assetId, this.edited = true});

  @override
  Future<RemoteOriginalImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(RemoteOriginalImageProvider key, ImageDecoderCallback decode) {
    return OneFramePlaceholderImageStreamCompleter(
      _codec(key, decode),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Asset Id', key.assetId),
      ],
      onLastListenerRemoved: cancel,
    );
  }

  Stream<ImageInfo> _codec(RemoteOriginalImageProvider key, ImageDecoderCallback decode) async* {
    if (isCancelled) {
      await evict();
      return;
    }

    final request = this.request = RemoteImageRequest(
      uri: getOriginalUrlForRemoteId(key.assetId, edited: key.edited),
      headers: ApiService.getRequestHeaders(),
    );
    yield* loadRequest(request, decode, isFinal: true);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is RemoteOriginalImageProvider) {
      return assetId == other.assetId && edited == other.edited;
    }

    return false;
  }

  @override
  int get hashCode => Object.hash(assetId, edited);
}
