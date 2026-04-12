import 'package:hooks_riverpod/hooks_riverpod.dart';

/// UX scope for the beta timeline asset viewer route.
///
/// When `true`, the viewer was opened from Library → Places (place-detail
/// timeline, i.e. the same intent as `TimelineArgs.closeViewerWhenAssetLeavesTimeline`
/// on the grid). The viewer route overrides this in a `ProviderScope` because
/// it is not a descendant of the timeline layout scope that exposes
/// `timelineArgsProvider`.
///
/// Default is `false` (e.g. main photo grid, deep links).
final assetViewerPlacesExitProvider = Provider<bool>((ref) => false);
