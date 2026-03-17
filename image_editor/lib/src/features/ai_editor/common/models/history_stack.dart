class HistoryStack<T> {
  HistoryStack(T initial) : _items = [initial], _index = 0;

  final List<T> _items;
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
    _index = _items.length - 1;
  }
}
