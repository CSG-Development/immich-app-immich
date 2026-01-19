import 'package:easy_localization/easy_localization.dart';

enum SortOrder { asc, desc }

enum TextSearchType { context, filename, description }

enum AssetVisibilityEnum { timeline, hidden, archive, locked }

enum SortUserBy { id }

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