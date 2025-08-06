import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/material.dart';
import 'package:image_editor/utils.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final Function(Uint8List) onImageEditingComplete;
  final VoidCallback onCloseEditor;

  const ImageEditor({
    super.key,
    required this.imageBytes,
    required this.onImageEditingComplete,
    required this.onCloseEditor,
  });

  @override
  State<ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<ImageEditor> {
  final _editorKey = GlobalKey<ProImageEditorState>();

  late ScrollController _bottomBarScrollController;

  late final EditorHistoryManager _historyManager;

  @override
  void initState() {
    super.initState();
    _bottomBarScrollController = ScrollController();
    _historyManager = EditorHistoryManager();
  }

  @override
  void dispose() {
    _bottomBarScrollController.dispose();
    _historyManager.dispose();
    super.dispose();
  }

  Future<void> _handleCustomEffectButton(ProImageEditorState editor) async {
    final currentBytes = await editor.editorImage?.safeByteArray();
    if (currentBytes == null) return;

    final currentPointer = editor.stateManager.historyPointer;
    await _historyManager.saveState(currentBytes, currentPointer);

    final transformedBytes = await monochromeEffect(currentBytes);
    await editor
        .updateBackgroundImage(EditorImage(byteArray: transformedBytes));
    editor.addHistory();
  }

  Future<void> _handleHistoryNavigation() async {
    final editor = _editorKey.currentState;
    if (editor == null) return;

    final currentPointer = editor.stateManager.historyPointer;
    final bytes = await _historyManager.getStateBytes(currentPointer);
    if (bytes != null) {
      await editor.updateBackgroundImage(EditorImage(byteArray: bytes));
    }
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

  Widget _buildEditorBottomBar(
    ProImageEditorState editor,
    Key key,
    BoxConstraints constraints,
  ) {
    return Scrollbar(
      key: key,
      controller: _bottomBarScrollController,
      scrollbarOrientation: ScrollbarOrientation.top,
      child: BottomAppBar(
        height: kBottomNavigationBarHeight,
        color: Colors.black,
        padding: EdgeInsets.zero,
        child: Center(
          child: SingleChildScrollView(
            controller: _bottomBarScrollController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: 500,
                maxWidth: 500,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildEditorButton(
                      label: 'Paint',
                      icon: Icons.edit_rounded,
                      onPressed: editor.openPaintEditor,
                    ),
                    _buildEditorButton(
                      label: 'Text',
                      icon: Icons.text_fields,
                      onPressed: editor.openTextEditor,
                    ),
                    _buildEditorButton(
                      label: 'Monochrome',
                      icon: Icons.filter_b_and_w,
                      onPressed: () => _handleCustomEffectButton(editor),
                      labelColor: Colors.amber,
                    ),
                    _buildEditorButton(
                      label: 'Crop/Rotate',
                      icon: Icons.crop_rotate_rounded,
                      onPressed: editor.openCropRotateEditor,
                    ),
                    _buildEditorButton(
                      label: 'Filter',
                      icon: Icons.filter,
                      onPressed: editor.openFilterEditor,
                    ),
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

  static const _bottomTextStyle = TextStyle(
    fontSize: 10.0,
    color: Colors.white,
  );

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.memory(
      widget.imageBytes,
      key: _editorKey,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          widget.onImageEditingComplete(bytes);
        },
        onCloseEditor: (_) => widget.onCloseEditor(),
        mainEditorCallbacks: MainEditorCallbacks(
          onUndo: _handleHistoryNavigation,
          onRedo: _handleHistoryNavigation,
        ),
      ),
      configs: ProImageEditorConfigs(
        designMode: platformDesignMode,
        /* mainEditor: MainEditorConfigs(
          widgets: MainEditorWidgets(
            bottomBar: (editor, rebuildStream, key) => ReactiveWidget(
              stream: rebuildStream,
              builder: (_) => LayoutBuilder(
                builder: (context, constraints) => _buildEditorBottomBar(
                  editor,
                  key,
                  constraints,
                ),
              ),
            ),
          ),
        ), */
      ),
    );
  }
}
