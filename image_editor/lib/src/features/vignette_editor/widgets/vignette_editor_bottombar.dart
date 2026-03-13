import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_item.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_matrix.dart';
import 'package:image_editor/src/features/vignette_editor/vignette_editor.dart';
import 'package:image_editor/src/widgets/adjustment_bottom_bar.dart';

/// Bottom bar for adjusting vignette parameters (intensity, radius, feather).
///
/// Thin wrapper around [AdjustmentBottomBar] so the vignette editor can reuse
/// the generic adjustment UI.
class VignetteEditorBottombar extends StatelessWidget {
  const VignetteEditorBottombar({
    super.key,
    required this.vignetteAdjustmentList,
    required this.vignetteAdjustmentMatrix,
    required this.rebuildController,
    required this.onChangedStart,
    required this.onChanged,
    required this.onChangedEnd,
    required this.bottomBarScrollCtrl,
    required this.state,
    required this.onSelect,
    required this.selectedIndex,
  });

  final List<VignetteAdjustmentItem> vignetteAdjustmentList;

  final List<VignetteAdjustmentMatrix> vignetteAdjustmentMatrix;

  final int selectedIndex;

  final StreamController<void> rebuildController;

  final ScrollController bottomBarScrollCtrl;

  final VignetteEditorState state;

  final Function(double value) onChangedStart;

  final Function(double value) onChanged;

  final Function(double value) onChangedEnd;

  final Function(int index) onSelect;

  @override
  Widget build(BuildContext context) {
    return AdjustmentBottomBar<VignetteAdjustmentItem, VignetteAdjustmentMatrix>(
      items: vignetteAdjustmentList,
      matrices: vignetteAdjustmentMatrix,
      rebuildController: rebuildController,
      bottomBarScrollCtrl: bottomBarScrollCtrl,
      selectedIndex: selectedIndex,
      onSelect: onSelect,
      onChangedStart: onChangedStart,
      onChanged: onChanged,
      onChangedEnd: onChangedEnd,
      topWidget: _VignetteColorPickerBar(
        selectedColor: state.vignetteColor,
        onColorChanged: state.setVignetteColor,
        theme: state.theme,
      ),
    );
  }
}

class _VignetteColorPickerBar extends StatelessWidget {
  const _VignetteColorPickerBar({required this.selectedColor, required this.onColorChanged, required this.theme});

  final Color selectedColor;
  final ValueChanged<Color> onColorChanged;
  final ThemeData theme;

  List<Color> get _palette => <Color>[
    Colors.black,
    Colors.white,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Colors.green,
    Colors.cyan,
    Colors.blue,
    Colors.indigo,
    Colors.purple,
    Colors.pink,
    Colors.brown,
    Colors.grey,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: _palette.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final color = _palette[index];
          final bool isSelected = color == selectedColor;
          final borderColor = isSelected ? theme.colorScheme.primary : Colors.white24;

          return GestureDetector(
            onTap: () => onColorChanged(color),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
              ),
            ),
          );
        },
      ),
    );
  }
}
