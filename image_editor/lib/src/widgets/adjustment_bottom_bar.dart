import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_editor/src/widgets/adjustment_item_base.dart';
import 'package:image_editor/src/widgets/adjustment_matrix_base.dart';
import 'package:pro_image_editor/shared/widgets/editor_scrollbar.dart';
import 'package:pro_image_editor/shared/widgets/flat_icon_text_button.dart';

/// Generic bottom bar for slider-based adjustments.
///
/// This widget can be reused by different editors (vignette, tune,
/// custom effects) by providing appropriate [AdjustmentItemBase] and
/// [AdjustmentMatrixBase] implementations.
class AdjustmentBottomBar<TItem extends AdjustmentItemBase, TMatrix extends AdjustmentMatrixBase>
    extends StatefulWidget {
  const AdjustmentBottomBar({
    super.key,
    required this.items,
    required this.matrices,
    required this.rebuildController,
    required this.bottomBarScrollCtrl,
    required this.selectedIndex,
    required this.onSelect,
    required this.onChangedStart,
    required this.onChanged,
    required this.onChangedEnd,
    this.topWidget,
  });

  /// Available adjustment items.
  final List<TItem> items;

  /// Current matrices for each item.
  final List<TMatrix> matrices;

  /// Currently selected item index.
  final int selectedIndex;

  /// Stream controller used to trigger rebuilds from external changes.
  final StreamController<void> rebuildController;

  /// Scroll controller for the horizontal item list.
  final ScrollController bottomBarScrollCtrl;

  /// Called when a new item is selected.
  final ValueChanged<int> onSelect;

  /// Called when slider interaction starts.
  final ValueChanged<double> onChangedStart;

  /// Called while slider value changes.
  final ValueChanged<double> onChanged;

  /// Called when slider interaction ends.
  final ValueChanged<double> onChangedEnd;

  /// Optional widget rendered above the slider (e.g. a color picker strip).
  final Widget? topWidget;

  @override
  State<AdjustmentBottomBar<TItem, TMatrix>> createState() => _AdjustmentBottomBarState<TItem, TMatrix>();
}

class _AdjustmentBottomBarState<TItem extends AdjustmentItemBase, TMatrix extends AdjustmentMatrixBase>
    extends State<AdjustmentBottomBar<TItem, TMatrix>> {
  final TextStyle _textStyle = const TextStyle(fontSize: 10.0);
  final double _iconSize = 22.0;

  late final ValueNotifier<double> _sliderValue = ValueNotifier<double>(widget.matrices[widget.selectedIndex].value);

  @override
  void didUpdateWidget(covariant AdjustmentBottomBar<TItem, TMatrix> oldWidget) {
    _sliderValue.value = widget.matrices[widget.selectedIndex].value;
    super.didUpdateWidget(oldWidget);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.only(top: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [if (widget.topWidget != null) widget.topWidget!, _buildSlider(), _buildItems()],
        ),
      ),
    );
  }

  Widget _buildSlider() {
    final activeOption = widget.items[widget.selectedIndex];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: RepaintBoundary(
        child: SizedBox(
          height: 40,
          child: ValueListenableBuilder<double>(
            valueListenable: _sliderValue,
            builder: (_, value, __) {
              return Slider(
                min: activeOption.min,
                max: activeOption.max,
                divisions: activeOption.divisions,
                label: value.toStringAsFixed(activeOption.decimalPlaces),
                value: value.clamp(activeOption.min, activeOption.max),
                onChangeStart: (val) {
                  _sliderValue.value = val;
                  widget.onChangedStart(val);
                },
                onChanged: (val) {
                  _sliderValue.value = val;
                  widget.onChanged(val);
                },
                onChangeEnd: widget.onChangedEnd,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildItems() {
    return SizedBox(
      height: kBottomNavigationBarHeight,
      child: EditorScrollbar(
        controller: widget.bottomBarScrollCtrl,
        child: SingleChildScrollView(
          controller: widget.bottomBarScrollCtrl,
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 0, 12.0, 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.items.length, (index) {
                final item = widget.items[index];
                final bool isSelected = widget.selectedIndex == index;
                final Color color = isSelected ? Colors.white : Colors.white.withValues(alpha: 0.6);

                return FlatIconTextButton(
                  label: Text(item.name, style: _textStyle.copyWith(color: color)),
                  icon: Icon(item.icon, size: _iconSize, color: color),
                  onPressed: () => widget.onSelect(index),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
