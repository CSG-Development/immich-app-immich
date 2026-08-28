import 'package:easy_localization/easy_localization.dart';

enum SortOrder {
  asc,
  desc;

  SortOrder reverse() {
    return this == SortOrder.asc ? SortOrder.desc : SortOrder.asc;
  }
}

enum TextSearchType { context, filename, description, ocr }

enum ActionSource { timeline, viewer }

enum AppLockTimeout {
  immediately('curator.lock_application_immediately', 0),
  m1('curator.lock_application_1_minute', 1),
  m5('curator.lock_application_5_minutes', 5),
  m30('curator.lock_application_30_minutes', 30);

  const AppLockTimeout(this.translationKey, this.durationinMinutes);
  final String translationKey;
  final int durationinMinutes;

  String tr() => translationKey.tr();
  Duration get during => Duration(minutes: durationinMinutes);
}

enum ShareAssetType { original, preview }

enum CleanupStep { selectDate, scan, delete }

enum AssetKeepType { none, photosOnly, videosOnly }

enum AssetDateAggregation { start, end }

enum SlideshowLook { contain, cover, blurredBackground }

enum SlideshowDirection { forward, backward, shuffle }

enum PartnerDirection { sharedBy, sharedWith }
