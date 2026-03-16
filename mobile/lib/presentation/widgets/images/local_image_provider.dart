import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/loaders/image_request.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/presentation/widgets/images/one_frame_multi_image_stream_completer.dart';
import 'package:immich_mobile/presentation/widgets/timeline/constants.dart';

class LocalThumbProvider extends CancellableImageProvider<LocalThumbProvider>
    with CancellableImageProviderMixin<LocalThumbProvider> {
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
    return OneFramePlaceholderImageStreamCompleter(
      _codec(key, decode),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<String>('Id', key.id),
        DiagnosticsProperty<Size>('Size', key.size),
      ],
      onDispose: cancel,
    );
  }

  Stream<ImageInfo> _codec(LocalThumbProvider key, ImageDecoderCallback decode) {
    final request = this.request = LocalImageRequest(localId: key.id, size: key.size, assetType: key.assetType);
    return loadRequest(request, decode);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is LocalThumbProvider) {
      return id == other.id;
    }
    return false;
  }

  @override
  int get hashCode => id.hashCode;
}

class LocalFullImageProvider extends CancellableImageProvider<LocalFullImageProvider>
    with CancellableImageProviderMixin<LocalFullImageProvider> {
  final String id;
  final Size size;
  final AssetType assetType;

  /// When true, the provider will skip the intermediate
  /// scaled request and go straight to loading the
  /// original file (Size.zero) as the first full frame.
  final bool originalOnly;

  LocalFullImageProvider({required this.id, required this.assetType, required this.size, this.originalOnly = false});

  @override
  Future<LocalFullImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture(this);
  }

  @override
  ImageStreamCompleter loadImage(LocalFullImageProvider key, ImageDecoderCallback decode) {
    return OneFramePlaceholderImageStreamCompleter(
      _codec(key, decode),
      // Still try to show a cached thumbnail as a fast placeholder,
      // even when originalOnly is true.
      initialImage: getInitialImage(LocalThumbProvider(id: key.id, assetType: key.assetType)),
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Id', key.id),
        DiagnosticsProperty<Size>('Size', key.size),
      ],
      onDispose: cancel,
    );
  }

  Stream<ImageInfo> _codec(LocalFullImageProvider key, ImageDecoderCallback decode) async* {
    yield* initialImageStream();

    if (isCancelled) {
      evict();
      return;
    }

    // When originalOnly is true, skip the intermediate scaled request
    // and go straight to the original file as the first full frame.
    if (originalOnly) {
      var request = this.request = LocalImageRequest(localId: key.id, assetType: key.assetType, size: Size.zero);
      yield* loadRequest(request, decode);
      return;
    }

    final devicePixelRatio = PlatformDispatcher.instance.views.first.devicePixelRatio;
    var request = this.request = LocalImageRequest(
      localId: key.id,
      size: Size(size.width * devicePixelRatio, size.height * devicePixelRatio),
      assetType: key.assetType,
    );

    yield* loadRequest(request, decode);

    if (!Store.get(StoreKey.loadOriginal, false)) {
      return;
    }

    if (isCancelled) {
      evict();
      return;
    }

    request = this.request = LocalImageRequest(localId: key.id, assetType: key.assetType, size: Size.zero);

    yield* loadRequest(request, decode);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is LocalFullImageProvider) {
      return id == other.id && size == other.size && originalOnly == other.originalOnly;
    }
    return false;
  }

  @override
  int get hashCode => id.hashCode ^ size.hashCode;
}
