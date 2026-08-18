import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Stubbed after Immich 3.x Drift migration.
/// Old Isar album/backup hooks were removed; album refresh now happens via
/// remote album / sync providers. Restore a Drift-based batcher if needed.
class AlbumRefreshBatcher {
  AlbumRefreshBatcher(this._ref, {this.batchSize = 5});

  // ignore: unused_field
  final Ref _ref;
  final int batchSize;

  void enqueue(Object upload) {}

  Future<void> flush() async {}
}
