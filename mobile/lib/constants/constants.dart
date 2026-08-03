import 'dart:io';

const int noDbId = -9223372036854775808; // from Isar
const double downloadCompleted = -1;
const double downloadFailed = -2;

const String kMobileMetadataKey = "mobile-app";

// Number of log entries retained in the log DB (trimmed on app start).
const int kLogTruncateLimit = 10000;

// In-memory ring buffer for the network debug overlay (resolver / monitor / OTP).
const int kNetworkDebugLogBufferLimit = 5000;

// Sync
const int kSyncEventBatchSize = 5000;
const int kFetchLocalAssetsBatchSize = 40000;

// Hash batch limits
final int kBatchHashFileLimit = Platform.isIOS ? 32 : 512;
const int kBatchHashSizeLimit = 1024 * 1024 * 1024; // 1GB

// Secure storage keys
const String kSecuredPinCode = "secured_pin_code";
const String kSecuredPasscode = "secured_passcode";
const String kSecuredPattern = "secured_pattern";

/// Marks a request as an asset upload. Stripped by ConnectionRecoveryInterceptor
/// before the request is sent, so it never reaches the server.
const String kUploadRequestHeader = 'x-curator-upload';

// background_downloader task groups
const String kManualUploadGroup = 'manual_upload_group';
const String kBackupGroup = 'backup_group';
const String kBackupLivePhotoGroup = 'backup_live_photo_group';
const String kDownloadGroupImage = 'group_image';
const String kDownloadGroupVideo = 'group_video';
const String kDownloadGroupLivePhoto = 'group_livephoto';

// Timeline constants
const int kTimelineNoneSegmentSize = 120;
const int kTimelineAssetLoadBatchSize = 1024;
const int kTimelineAssetLoadOppositeSize = 64;

// Widget keys
const String appShareGroupId = "group.com.seagate.curator.stxphotos.ios.share";
const String kWidgetAuthToken = "widget_auth_token";
const String kWidgetServerEndpoint = "widget_server_url";
const String kWidgetCustomHeaders = "widget_custom_headers";

// add widget identifiers here for new widgets
// these are used to force a widget refresh
// (iOSName, androidFQDN)
const List<(String, String)> kWidgetNames = [
  // iOS widget name, Android fully-qualified AppWidgetProvider class name
  ('com.seagate.curator.stxphotos.widget.random', 'com.seagate.curator.stxphotos.android.widget.RandomReceiver'),
  ('com.seagate.curator.stxphotos.widget.memory', 'com.seagate.curator.stxphotos.android.widget.MemoryReceiver'),
];

const double kUploadStatusFailed = -1.0;
const double kUploadStatusCanceled = -2.0;

const int kMinMonthsToEnableScrubberSnap = 12;

const String kImmichAppStoreLink = "https://apps.apple.com/app/immich/id1613945652";
const String kImmichPlayStoreLink =
    "https://play.google.com/store/apps/details?id=com.seagate.curator.stxphotos.android";
const String kImmichLatestRelease = "https://github.com/immich-app/immich/releases/latest";

const int kPhotoTabIndex = 0;
const int kSearchTabIndex = 1;
const int kAlbumTabIndex = 2;
const int kLibraryTabIndex = 3;

// Workaround for SQLite's variable limit (SQLITE_MAX_VARIABLE_NUMBER = 32766)
const int kDriftMaxChunk = 32000;
