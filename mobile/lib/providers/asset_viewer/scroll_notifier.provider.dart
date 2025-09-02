import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

final scrollToTopNotifierProvider = ScrollNotifier();

final scrollNotifierProvider =
    ChangeNotifierProvider<ScrollNotifier>((ref) => ScrollNotifier());

class ScrollNotifier with ChangeNotifier {
  void scrollToTop() {
    notifyListeners();
  }

  bool _isVisible = false;
  double _lastOffset = 0;
  bool _isOverscrolling = false;

  bool get isVisible => _isVisible;

  void handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final offset = notification.metrics.pixels;
      final maxScrollExtent = notification.metrics.maxScrollExtent;
      final minScrollExtent = notification.metrics.minScrollExtent;
      
      // Check if we're in an overscroll state (iOS bounce effect)
      if (offset < minScrollExtent || offset > maxScrollExtent) {
        if (!_isOverscrolling) {
          _isOverscrolling = true;
        }
        return; // Don't update navbar visibility during overscroll
      } else {
        _isOverscrolling = false;
      }
      
      _updateVisibility(offset);
    } else if (notification is OverscrollNotification) {
      // Handle overscroll notifications (iOS bounce)
      _isOverscrolling = true;
      return; // Don't update navbar visibility during overscroll
    } else if (notification is ScrollEndNotification) {
      // Reset overscroll state when scroll ends
      _isOverscrolling = false;
    }
  }

  void handleItemPositionsChange(Iterable<ItemPosition> positions) {
    if (positions.isEmpty) return;
    
    // Don't update visibility if we're in an overscroll state
    if (_isOverscrolling) return;
    
    final minIndex = positions
        .where((pos) => pos.itemTrailingEdge > 0)
        .reduce((min, pos) => pos.index < min.index ? pos : min)
        .index
        .toDouble();
    _updateVisibility(minIndex);
  }

  void _updateVisibility(double current) {
    // Don't update visibility if we're in an overscroll state
    if (_isOverscrolling) return;
    
    if (current > _lastOffset && _isVisible) {
      _isVisible = false;
      notifyListeners();
    } else if (current < _lastOffset && !_isVisible) {
      _isVisible = true;
      notifyListeners();
    }
    _lastOffset = current;
  }
}
