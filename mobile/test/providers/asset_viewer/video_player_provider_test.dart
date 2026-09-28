import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/providers/asset_viewer/video_player_provider.dart';
import 'package:native_video_player/native_video_player.dart';

void main() {
  const channelName = 'me.albemala.native_video_player.api.1';
  const codec = StandardMethodCodec();

  late NativeVideoPlayerController controller;
  late VideoPlayerNotifier notifier;
  late int reportedDurationMs;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    reportedDurationMs = 12345;

    // Simulate the platform side of the player's method channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(channelName),
      (MethodCall call) async {
        switch (call.method) {
          case 'getVideoInfo':
            return {'height': 1080, 'width': 1920, 'duration': reportedDurationMs};
          default:
            return null;
        }
      },
    );

    // ignore: invalid_use_of_protected_member
    controller = NativeVideoPlayerController(1);
    notifier = VideoPlayerNotifier();
    notifier.attachController(controller);
    // Mirrors the wiring in NativeVideoViewer (video_viewer.widget.dart)
    controller.onPlaybackReady.addListener(notifier.onNativePlaybackReady);
    addTearDown(() {
      // ignore: invalid_use_of_protected_member
      controller.dispose();
    });
  });

  Future<void> emitPlaybackReady() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      channelName,
      codec.encodeMethodCall(const MethodCall('onPlaybackReady')),
      (_) {},
    );
    await pumpEventQueue();
  }

  group('VideoPlayerNotifier.onNativePlaybackReady', () {
    test('applies duration from a ready event', () async {
      await emitPlaybackReady();

      expect(notifier.state.duration, const Duration(milliseconds: 12345));
    });

    test('does not poison state when duration is unknown (-1) and recovers on next ready', () async {
      // ExoPlayer reports Cms.DURATION_UNKNOWN (-1) when STATE_READY fires
      // before the duration is known (documented in plugin issue
      // albemala/native_video_player#48/#55).
      reportedDurationMs = -1;
      await emitPlaybackReady();

      expect(notifier.state.duration, Duration.zero);

      // A later ready event carries the real duration once the player knows it.
      reportedDurationMs = 12345;
      await emitPlaybackReady();

      expect(notifier.state.duration, const Duration(milliseconds: 12345));
    });

    test('does not poison state when duration is zero', () async {
      reportedDurationMs = 0;
      await emitPlaybackReady();

      expect(notifier.state.duration, Duration.zero);
    });
  });
}
