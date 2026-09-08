import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';

final shareIntentNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final shareIntentPendingProvider = NotifierProvider<ShareIntentPendingNotifier, List<ShareIntentAttachment>?>(
  ShareIntentPendingNotifier.new,
);

class ShareIntentPendingNotifier extends Notifier<List<ShareIntentAttachment>?> {
  static const _ttl = Duration(minutes: 10);

  DateTime? _deferredAt;

  @override
  List<ShareIntentAttachment>? build() => null;

  void defer(List<ShareIntentAttachment> attachments) {
    _deferredAt = ref.read(shareIntentNowProvider)();
    state = List<ShareIntentAttachment>.unmodifiable(attachments);
  }

  List<ShareIntentAttachment>? takeIfFresh() {
    final attachments = state;
    final deferredAt = _deferredAt;
    state = null;
    _deferredAt = null;

    if (attachments == null || attachments.isEmpty) {
      return null;
    }

    if (deferredAt != null && ref.read(shareIntentNowProvider)().difference(deferredAt) > _ttl) {
      return null;
    }

    return attachments;
  }
}
