import 'package:flutter/widgets.dart';
import 'package:image_editor/src/models/image_editor_translations.dart';

class ImageEditorTranslationScope extends InheritedWidget {
  const ImageEditorTranslationScope({
    super.key,
    required this.translations,
    required super.child,
  });

  final ImageEditorTranslations translations;

  static ImageEditorTranslations of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ImageEditorTranslationScope>();
    return scope?.translations ?? const ImageEditorTranslations();
  }

  static String text(BuildContext context, String key, String fallback) {
    return of(context).resolve(key, fallback);
  }

  @override
  bool updateShouldNotify(covariant ImageEditorTranslationScope oldWidget) {
    return oldWidget.translations != translations;
  }
}
