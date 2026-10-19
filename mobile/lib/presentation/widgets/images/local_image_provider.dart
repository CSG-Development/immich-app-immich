import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/infrastructure/loaders/image_request.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/presentation/widgets/images/animated_image_stream_completer.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/presentation/widgets/images/one_frame_multi_image_stream_completer.dart';
import 'package:immich_mobile/presentation/widgets/timeline/constants.dart';

class LocalThumbProvider extends ImageProvider<LocalThumbProvider> {
  final String id;
  final Size size;
  final AssetType assetType;

  LocalThumbProvider({required this.id, required this.assetType, this.size = kThumbnailResolution});

  @override
  Future<LocalThumbProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(LocalThumbProvider key, ImageDecoderCallback decode) {
    final loader = ImageLoader(key);
    return OneFramePlaceholderImageStreamCompleter(
      _codec(loader, key, decode),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('Id', key.id),
        DiagnosticsProperty<Size>('Size', key.size),
      ],
      onLastListenerRemoved: loader.cancel,
    );
  }

  Stream<ImageInfo> _codec(ImageLoader loader, LocalThumbProvider key, ImageDecoderCallback decode) {
    final request = loader.request = LocalImageRequest(localId: key.id, size: key.size, assetType: key.assetType);
    return loader.loadRequest(request, decode, isFinal: true);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is LocalThumbProvider) {
      return id == other.id;
    }
    return false;
  }

  @override
  int get hashCode => id.hashCode;
}

class LocalFullImageProvider extends ImageProvider<LocalFullImageProvider> {
  final String id;
  final Size size;
  final AssetType assetType;
  final bool isAnimated;

  final bool originalOnly;

  LocalFullImageProvider({
    required this.id,
    required this.assetType,
    required this.size,
    required this.isAnimated,
    this.originalOnly = false,
  });

  @override
  Future<LocalFullImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(LocalFullImageProvider key, ImageDecoderCallback decode) {
    final loader = ImageLoader(key);
    if (key.isAnimated) {
      return AnimatedImageStreamCompleter(
        stream: _animatedCodec(loader, key, decode),
        scale: 1.0,
        initialImage: loader.getInitialImage(LocalThumbProvider(id: key.id, assetType: key.assetType)),
        informationCollector: () => <DiagnosticsNode>[
          DiagnosticsProperty<ImageProvider>('Image provider', this),
          DiagnosticsProperty<String>('Id', key.id),
          DiagnosticsProperty<Size>('Size', key.size),
          DiagnosticsProperty<bool>('isAnimated', key.isAnimated),
        ],
        onLastListenerRemoved: loader.cancel,
      );
    }

    return OneFramePlaceholderImageStreamCompleter(
      _codec(loader, key, decode),
      initialImage: key.originalOnly
          ? null
          : loader.getInitialImage(LocalThumbProvider(id: key.id, assetType: key.assetType)),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Id', key.id),
        DiagnosticsProperty<Size>('Size', key.size),
        DiagnosticsProperty<bool>('isAnimated', key.isAnimated),
      ],
      onLastListenerRemoved: loader.cancel,
    );
  }

  Stream<ImageInfo> _codec(ImageLoader loader, LocalFullImageProvider key, ImageDecoderCallback decode) async* {
    if (key.originalOnly) {
      if (loader.isCancelled) {
        return;
      }
      final request = loader.request = LocalImageRequest(localId: key.id, assetType: key.assetType, size: Size.zero);
      yield* loader.loadRequest(request, decode, isFinal: true);
      return;
    }

    yield* loader.initialImageStream();

    if (loader.isCancelled) {
      return;
    }

    final loadOriginal = SettingsRepository.instance.appConfig.image.loadOriginal;
    final devicePixelRatio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    var request = loader.request = LocalImageRequest(
      localId: key.id,
      size: Size(size.width * devicePixelRatio, size.height * devicePixelRatio),
      assetType: key.assetType,
    );
    yield* loader.loadRequest(request, decode, isFinal: !loadOriginal);

    if (!loadOriginal) {
      return;
    }

    if (loader.isCancelled) {
      return;
    }

    request = loader.request = LocalImageRequest(localId: key.id, assetType: key.assetType, size: Size.zero);

    yield* loader.loadRequest(request, decode, isFinal: true);
  }

  Stream<Object> _animatedCodec(ImageLoader loader, LocalFullImageProvider key, ImageDecoderCallback decode) async* {
    yield* loader.initialImageStream();

    if (loader.isCancelled) {
      return;
    }

    final devicePixelRatio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    final previewRequest = loader.request = LocalImageRequest(
      localId: key.id,
      size: Size(size.width * devicePixelRatio, size.height * devicePixelRatio),
      assetType: key.assetType,
    );
    yield* loader.loadRequest(previewRequest, decode, isFinal: false);

    if (loader.isCancelled) {
      return;
    }

    // always try original for animated, since previews don't support animation
    final originalRequest = loader.request = LocalImageRequest(
      localId: key.id,
      size: Size.zero,
      assetType: key.assetType,
    );
    final codec = await loader.loadCodecRequest(originalRequest, isFinal: true);
    if (codec == null) {
      if (loader.isCancelled) {
        return;
      }
      throw StateError('Failed to load animated codec for local asset ${key.id}');
    }
    yield codec;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is LocalFullImageProvider) {
      return id == other.id &&
          size == other.size &&
          isAnimated == other.isAnimated &&
          originalOnly == other.originalOnly;
    }
    return false;
  }

  @override
  int get hashCode => id.hashCode ^ size.hashCode ^ isAnimated.hashCode ^ originalOnly.hashCode;
}
