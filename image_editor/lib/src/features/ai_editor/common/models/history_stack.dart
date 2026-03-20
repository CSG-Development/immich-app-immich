class HistoryStack<T> {
  HistoryStack(T initial, {this.maxItems}) : _items = [initial], _index = 0;

  final List<T> _items;
  final int? maxItems;
  int _index;

  T get current => _items[_index];
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _items.length - 1;

  bool undo() {
    if (!canUndo) return false;
    _index -= 1;
    return true;
  }

  bool redo() {
    if (!canRedo) return false;
    _index += 1;
    return true;
  }

  void push(T value) {
    if (_index < _items.length - 1) {
      _items.removeRange(_index + 1, _items.length);
    }
    _items.add(value);
    if (maxItems != null && maxItems! > 0 && _items.length > maxItems!) {
      final removeCount = _items.length - maxItems!;
      _items.removeRange(0, removeCount);
      _index = (_index - removeCount).clamp(0, _items.length - 1);
    }
    _index = _items.length - 1;
  }
}
