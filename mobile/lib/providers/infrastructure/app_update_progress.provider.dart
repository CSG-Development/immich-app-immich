import 'package:hooks_riverpod/hooks_riverpod.dart';

class UpdateDownloadState {
  final int percent;
  final bool isDownloading;
  final String? errorMessage;

  const UpdateDownloadState({
    this.percent = 0,
    this.isDownloading = false,
    this.errorMessage,
  });

  UpdateDownloadState copyWith({
    int? percent,
    bool? isDownloading,
    String? errorMessage,
  }) => UpdateDownloadState(
        percent: percent ?? this.percent,
        isDownloading: isDownloading ?? this.isDownloading,
        errorMessage: errorMessage,
      );
}

class UpdateDownloadNotifier extends StateNotifier<UpdateDownloadState> {
  UpdateDownloadNotifier() : super(const UpdateDownloadState());

  void start() => state = state.copyWith(isDownloading: true, percent: 0, errorMessage: null);
  void setProgress(int percent) => state = state.copyWith(percent: percent);
  void error(String message) => state = state.copyWith(isDownloading: false, errorMessage: message);
  void complete() => state = state.copyWith(isDownloading: false, percent: 100, errorMessage: null);
  void reset() => state = const UpdateDownloadState();
}

final updateDownloadProvider = StateNotifierProvider<UpdateDownloadNotifier, UpdateDownloadState>((ref) {
  return UpdateDownloadNotifier();
});


