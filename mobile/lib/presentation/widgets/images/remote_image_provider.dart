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

class RemoteImageProvider extends ImageProvider<RemoteImageProvider> {
  final String? _fixedUrl;
  final String? assetId;
  final String? thumbhash;
  final bool edited;

  RemoteImageProvider({required String url, this.edited = true}) : _fixedUrl = url, assetId = null, thumbhash = null;

  RemoteImageProvider.thumbnail({required String this.assetId, required String this.thumbhash, this.edited = true})
    : _fixedUrl = null;

  String get url => _fixedUrl ?? getThumbnailUrlForRemoteId(assetId!, thumbhash: thumbhash, edited: edited);

  @override
  Future<RemoteImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(RemoteImageProvider key, ImageDecoderCallback decode) {
    final loader = ImageLoader(key);
    return OneFramePlaceholderImageStreamCompleter(
      _codec(loader, key, decode),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('URL', key.url),
      ],
      onLastListenerRemoved: loader.cancel,
    );
  }

  Stream<ImageInfo> _codec(ImageLoader loader, RemoteImageProvider key, ImageDecoderCallback decode) {
    final request = loader.request = RemoteImageRequest(uri: key.url, headers: ApiService.getRequestHeaders());
    return loader.loadRequest(request, decode, isFinal: true);
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

class RemoteFullImageProvider extends ImageProvider<RemoteFullImageProvider> {
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
    final loader = ImageLoader(key);
    if (key.isAnimated) {
      return AnimatedImageStreamCompleter(
        stream: _animatedCodec(loader, key, decode),
        scale: 1.0,
        initialImage: loader.getInitialImage(
          RemoteImageProvider.thumbnail(assetId: key.assetId, thumbhash: key.thumbhash, edited: key.edited),
        ),
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<ImageProvider>('Image provider', this),
          DiagnosticsProperty<String>('Asset Id', key.assetId),
          DiagnosticsProperty<bool>('isAnimated', key.isAnimated),
        ],
        onLastListenerRemoved: loader.cancel,
      );
    }

    return OneFramePlaceholderImageStreamCompleter(
      _codec(loader, key, decode),
      initialImage: loader.getInitialImage(
        RemoteImageProvider.thumbnail(assetId: key.assetId, thumbhash: key.thumbhash, edited: key.edited),
      ),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Asset Id', key.assetId),
        DiagnosticsProperty<bool>('isAnimated', key.isAnimated),
      ],
      onLastListenerRemoved: loader.cancel,
    );
  }

  Stream<ImageInfo> _codec(ImageLoader loader, RemoteFullImageProvider key, ImageDecoderCallback decode) async* {
    yield* loader.initialImageStream();

    if (loader.isCancelled) {
      return;
    }

    final previewRequest = loader.request = RemoteImageRequest(
      uri: getThumbnailUrlForRemoteId(
        key.assetId,
        type: AssetMediaSize.preview,
        thumbhash: key.thumbhash,
        edited: key.edited,
      ),
      headers: ApiService.getRequestHeaders(),
    );
    final loadOriginal = assetType == AssetType.image && SettingsRepository.instance.appConfig.image.loadOriginal;
    yield* loader.loadRequest(previewRequest, decode, isFinal: !loadOriginal);

    if (!loadOriginal) {
      return;
    }

    if (loader.isCancelled) {
      return;
    }

    final originalRequest = loader.request = RemoteImageRequest(
      uri: getOriginalUrlForRemoteId(key.assetId, edited: key.edited),
      headers: ApiService.getRequestHeaders(),
    );
    yield* loader.loadRequest(originalRequest, decode, isFinal: true);
  }

  Stream<Object> _animatedCodec(ImageLoader loader, RemoteFullImageProvider key, ImageDecoderCallback decode) async* {
    yield* loader.initialImageStream();

    if (loader.isCancelled) {
      return;
    }

    final previewRequest = loader.request = RemoteImageRequest(
      uri: getThumbnailUrlForRemoteId(
        key.assetId,
        type: AssetMediaSize.preview,
        thumbhash: key.thumbhash,
        edited: key.edited,
      ),
      headers: ApiService.getRequestHeaders(),
    );
    yield* loader.loadRequest(previewRequest, decode, isFinal: false);

    if (loader.isCancelled) {
      return;
    }

    // always try original for animated, since previews don't support animation
    final originalRequest = loader.request = RemoteImageRequest(
      uri: getOriginalUrlForRemoteId(key.assetId, edited: key.edited),
      headers: ApiService.getRequestHeaders(),
    );
    final codec = await loader.loadCodecRequest(originalRequest, isFinal: true);
    if (codec == null) {
      if (loader.isCancelled) {
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

class RemoteOriginalImageProvider extends ImageProvider<RemoteOriginalImageProvider> {
  final String assetId;
  final bool edited;

  RemoteOriginalImageProvider({required this.assetId, this.edited = true});

  @override
  Future<RemoteOriginalImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(RemoteOriginalImageProvider key, ImageDecoderCallback decode) {
    final loader = ImageLoader(key);
    return OneFramePlaceholderImageStreamCompleter(
      _codec(loader, key, decode),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Asset Id', key.assetId),
      ],
      onLastListenerRemoved: loader.cancel,
    );
  }

  Stream<ImageInfo> _codec(ImageLoader loader, RemoteOriginalImageProvider key, ImageDecoderCallback decode) async* {
    if (loader.isCancelled) {
      return;
    }

    final request = loader.request = RemoteImageRequest(
      uri: getOriginalUrlForRemoteId(key.assetId, edited: key.edited),
      headers: ApiService.getRequestHeaders(),
    );
    yield* loader.loadRequest(request, decode, isFinal: true);
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
