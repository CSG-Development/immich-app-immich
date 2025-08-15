import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

final scrollToTopNotifierProvider = ScrollNotifier();

final scrollNotifierProvider =
    ChangeNotifierProvider<ScrollNotifier>((ref) => ScrollNotifier());

class ScrollNotifier with ChangeNotifier {
  void scrollToTop() {
    notifyListeners();
  }

  bool _isVisible = true;
  double _lastOffset = 0;

  bool get isVisible => _isVisible;

  void handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final offset = notification.metrics.pixels;
      _updateVisibility(offset);
    }
  }

  void handleItemPositionsChange(Iterable<ItemPosition> positions) {
    if (positions.isEmpty) return;
    final minIndex = positions
        .where((pos) => pos.itemTrailingEdge > 0)
        .reduce((min, pos) => pos.index < min.index ? pos : min)
        .index
        .toDouble();
    _updateVisibility(minIndex);
  }

  void _updateVisibility(double current) {
    if (current > _lastOffset && _isVisible) {
      _isVisible = false;
      notifyListeners();
    } else if (current < _lastOffset && !_isVisible) {
      _isVisible = true;
      notifyListeners();
    }
    _lastOffset = current;
  }

  void setIsVisible(bool isVisible) {
    _isVisible = isVisible;
    notifyListeners();
  }
}
