import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Custom bottom bar for the image editor
class EditorBottomBar extends StatelessWidget {
  final ProImageEditorState editor;
  final Stream<void> rebuildStream;
  final VoidCallback? onCustomEffect;

  const EditorBottomBar({super.key, required this.editor, required this.rebuildStream, this.onCustomEffect});

  @override
  Widget build(BuildContext context) {
    return ReactiveWidget(
      stream: rebuildStream,
      builder: (_) => LayoutBuilder(builder: (context, constraints) => _buildBottomBar(context, constraints)),
    );
  }

  Widget _buildBottomBar(BuildContext context, BoxConstraints constraints) {
    return Scrollbar(
      scrollbarOrientation: ScrollbarOrientation.top,
      child: BottomAppBar(
        height: kBottomNavigationBarHeight,
        color: Colors.black,
        padding: EdgeInsets.zero,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 500, maxWidth: 500),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEditorButton(label: 'Paint', icon: Icons.edit_rounded, onPressed: editor.openPaintEditor),
                    _buildEditorButton(label: 'Text', icon: Icons.text_fields, onPressed: editor.openTextEditor),
                    if (onCustomEffect != null)
                      _buildEditorButton(
                        label: 'Monochrome',
                        icon: Icons.filter_b_and_w,
                        onPressed: onCustomEffect!,
                        labelColor: Colors.amber,
                      ),
                    _buildEditorButton(
                      label: 'Crop/Rotate',
                      icon: Icons.crop_rotate_rounded,
                      onPressed: editor.openCropRotateEditor,
                    ),
                    _buildEditorButton(label: 'Tune', icon: Icons.tune, onPressed: editor.openTuneEditor),
                    _buildEditorButton(label: 'Filter', icon: Icons.filter, onPressed: editor.openFilterEditor),
                    _buildEditorButton(
                      label: 'Emoji',
                      icon: Icons.sentiment_satisfied_alt_rounded,
                      onPressed: editor.openEmojiEditor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    Color? labelColor,
  }) {
    return FlatIconTextButton(
      label: Text(label, style: _bottomTextStyle.copyWith(color: labelColor)),
      icon: Icon(icon, size: 22, color: Colors.white),
      onPressed: onPressed,
    );
  }

  static const _bottomTextStyle = TextStyle(fontSize: 10.0, color: Colors.white);
}
