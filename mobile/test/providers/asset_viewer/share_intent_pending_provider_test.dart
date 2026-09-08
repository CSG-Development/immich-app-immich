import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_pending.provider.dart';

void main() {
  late DateTime now;
  late ProviderContainer container;

  final attachments = [
    ShareIntentAttachment(
      path: '/tmp/file.jpg',
      type: ShareIntentAttachmentType.image,
      status: UploadStatus.enqueued,
    ),
  ];

  setUp(() {
    now = DateTime(2026, 4, 17, 12);
    container = ProviderContainer(
      overrides: [shareIntentNowProvider.overrideWithValue(() => now)],
    );
    addTearDown(container.dispose);
  });

  test('defer stores pending attachments', () {
    container.read(shareIntentPendingProvider.notifier).defer(attachments);

    expect(container.read(shareIntentPendingProvider), attachments);
  });

  test('takeIfFresh returns pending attachments once', () {
    container.read(shareIntentPendingProvider.notifier).defer(attachments);

    final first = container.read(shareIntentPendingProvider.notifier).takeIfFresh();
    final second = container.read(shareIntentPendingProvider.notifier).takeIfFresh();

    expect(first, attachments);
    expect(second, isNull);
  });

  test('takeIfFresh drops expired attachments', () {
    container.read(shareIntentPendingProvider.notifier).defer(attachments);
    now = now.add(const Duration(minutes: 11));

    final result = container.read(shareIntentPendingProvider.notifier).takeIfFresh();

    expect(result, isNull);
    expect(container.read(shareIntentPendingProvider), isNull);
  });

  test('newer deferred attachments replace older ones', () {
    final newerAttachments = [
      ShareIntentAttachment(
        path: '/tmp/file-2.jpg',
        type: ShareIntentAttachmentType.image,
        status: UploadStatus.enqueued,
      ),
    ];

    container.read(shareIntentPendingProvider.notifier).defer(attachments);
    container.read(shareIntentPendingProvider.notifier).defer(newerAttachments);

    final result = container.read(shareIntentPendingProvider.notifier).takeIfFresh();

    expect(result, newerAttachments);
  });
}
