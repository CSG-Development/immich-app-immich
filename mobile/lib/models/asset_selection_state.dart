import 'package:immich_mobile/entities/asset.entity.dart';

class AssetSelectionState {
  final bool hasRemote;
  final bool hasLocal;
  final bool hasMerged;
  final bool hasMergedTrashed;
  final bool hasLocalOnly;
  final int selectedCount;

  const AssetSelectionState({
    this.hasRemote = false,
    this.hasLocal = false,
    this.hasMerged = false,
    this.hasMergedTrashed = false,
    this.hasLocalOnly = false,
    this.selectedCount = 0,
  });

  AssetSelectionState copyWith({
    bool? hasRemote,
    bool? hasLocal,
    bool? hasMerged,
    bool? hasMergedTrashed,
    bool? hasLocalOnly,
    int? selectedCount,
  }) {
    return AssetSelectionState(
      hasRemote: hasRemote ?? this.hasRemote,
      hasLocal: hasLocal ?? this.hasLocal,
      hasMerged: hasMerged ?? this.hasMerged,
      hasMergedTrashed: hasMergedTrashed ?? this.hasMergedTrashed,
      hasLocalOnly: hasLocalOnly ?? this.hasLocalOnly,
      selectedCount: selectedCount ?? this.selectedCount,
    );
  }

  AssetSelectionState.fromSelection(Set<Asset> selection)
      : hasLocal = selection.any((e) => e.isLocal),
        // Treat remotely-trashed assets as not having remote capabilities
        hasMerged = selection.any(
          (e) => e.storage == AssetState.merged && !e.isTrashed,
        ),
        hasRemote = selection.any(
          (e) => e.storage == AssetState.remote && !e.isTrashed,
        ),
        hasMergedTrashed = selection.any(
          (e) => e.storage == AssetState.merged && e.isTrashed,
        ),
        hasLocalOnly = selection.any(
          (e) => e.storage == AssetState.local,
        ),
        selectedCount = selection.length;

  @override
  String toString() =>
      'SelectionAssetState(hasRemote: $hasRemote, hasLocal: $hasLocal, hasMerged: $hasMerged, hasMergedTrashed: $hasMergedTrashed, hasLocalOnly: $hasLocalOnly, selectedCount: $selectedCount)';

  @override
  bool operator ==(covariant AssetSelectionState other) {
    if (identical(this, other)) return true;

    return other.hasRemote == hasRemote &&
        other.hasLocal == hasLocal &&
        other.hasMerged == hasMerged &&
        other.hasMergedTrashed == hasMergedTrashed &&
        other.hasLocalOnly == hasLocalOnly &&
        other.selectedCount == selectedCount;
  }

  @override
  int get hashCode =>
      hasRemote.hashCode ^
      hasLocal.hashCode ^
      hasMerged.hashCode ^
      hasMergedTrashed.hashCode ^
      hasLocalOnly.hashCode ^
      selectedCount.hashCode;
}
