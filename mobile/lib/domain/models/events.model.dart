import 'package:immich_mobile/domain/utils/event_stream.dart';

// Timeline Events
class TimelineReloadEvent extends Event {
  const TimelineReloadEvent();
}

class ScrollToTopEvent extends Event {
  const ScrollToTopEvent();
}

class ScrollToDateEvent extends Event {
  final DateTime date;

  const ScrollToDateEvent(this.date);
}

// Asset Viewer Events
class ViewerShowDetailsEvent extends Event {
  const ViewerShowDetailsEvent();
}

class ViewerReloadAssetEvent extends Event {
  const ViewerReloadAssetEvent();
}

/// Emitted after a successful location edit when the viewer was opened from
/// Library → Places (see [TimelineArgs.closeViewerWhenAssetLeavesTimeline]).
class ViewerExitAfterPlacesLocationEditEvent extends Event {
  const ViewerExitAfterPlacesLocationEditEvent();
}

class ViewerStackAssetDeletedEvent extends Event {
  final int stackIndex;

  const ViewerStackAssetDeletedEvent({required this.stackIndex});
}

// Multi-Select Events
class MultiSelectToggleEvent extends Event {
  final bool isEnabled;
  const MultiSelectToggleEvent(this.isEnabled);
}

// Map Events
class MapMarkerReloadEvent extends Event {
  const MapMarkerReloadEvent();
}

/// Emitted after a successful endpoint activation (including same-host reconnect).
/// Visible thumbnails that never finished loading can retry against the active URL.
class RemoteImagesInvalidateEvent extends Event {
  const RemoteImagesInvalidateEvent();
}
