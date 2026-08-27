import 'dart:convert';

import 'package:immich_mobile/domain/models/album/album.model.dart';
// ignore: import_rule_openapi
import 'package:openapi/api.dart' as openapi;

sealed class AlbumEditAccessResult {
  const AlbumEditAccessResult();
}

final class AlbumEditAccessAllowed extends AlbumEditAccessResult {
  final RemoteAlbum album;
  const AlbumEditAccessAllowed(this.album);
}

final class AlbumEditAccessViewOnly extends AlbumEditAccessResult {
  final RemoteAlbum album;
  const AlbumEditAccessViewOnly(this.album);
}

final class AlbumEditAccessDenied extends AlbumEditAccessResult {
  const AlbumEditAccessDenied();
}

final class AlbumEditAccessDeleted extends AlbumEditAccessResult {
  const AlbumEditAccessDeleted();
}

bool isAlbumEditor(openapi.AlbumResponseDto album, String userId, String ownerId) {
  return ownerId == userId ||
      album.albumUsers.any(
        (albumUser) => albumUser.user.id == userId && albumUser.role == openapi.AlbumUserRole.editor,
      );
}

AlbumEditAccessResult classifyAlbumAccessError(Object error) {
  final message = _serverMessage(error) ?? '';
  if (RegExp(r'album has been deleted|album not found', caseSensitive: false).hasMatch(message)) {
    return const AlbumEditAccessDeleted();
  }
  return const AlbumEditAccessDenied();
}

bool isAlbumPermissionError(Object error) {
  final message = _serverMessage(error) ?? '';
  return RegExp(
    r'album\.read|albumAsset\.create|album has been deleted|album not found',
    caseSensitive: false,
  ).hasMatch(message);
}

String albumAccessMessageKey(AlbumEditAccessResult result) {
  return switch (result) {
    AlbumEditAccessViewOnly() => 'album_permissions_changed_view_only',
    AlbumEditAccessDenied() => 'album_access_denied',
    AlbumEditAccessDeleted() => 'album_deleted_by_owner',
    AlbumEditAccessAllowed() => throw ArgumentError('No message key for allowed access'),
  };
}

String? _serverMessage(Object error) {
  if (error is! openapi.ApiException || error.innerException != null || error.message == null) {
    return null;
  }

  try {
    final body = jsonDecode(error.message!);
    if (body is Map && body['message'] != null) {
      final message = body['message'];
      return message is List ? message.join(', ') : message.toString();
    }
  } catch (_) {}
  return error.message;
}
