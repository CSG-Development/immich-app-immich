import 'dart:async' show TimeoutException;
import 'dart:io' show HandshakeException, HttpStatus, SocketException;

import 'package:chopper/chopper.dart';

class RefreshFailureClassifier {
  static bool shouldLogoutOnRefreshFailure(Object error) {
    // Chopper Response errors carry HTTP status codes.
    if (error is Response) {
      final status = error.statusCode;
      // 401/403 indicate the refresh token itself is invalid/expired.
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        return true;
      }

      // Some backends return 400 with "invalid_grant"/invalid refresh details.
      if (status == HttpStatus.badRequest) {
        final payload = '${error.error ?? ''} ${error.body ?? ''}';
        return _hasInvalidRefreshHint(payload);
      }
      return false;
    }

    // Network and TLS failures are transient and should not force logout.
    if (error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException) {
      return false;
    }

    // Fallback for wrapped exceptions.
    final message = error.toString().toLowerCase();
    return (message.contains('401') && message.contains('unauthorized')) ||
        (message.contains('403') && message.contains('forbidden')) ||
        _hasInvalidRefreshHint(message);
  }

  static bool _hasInvalidRefreshHint(String text) {
    final message = text.toLowerCase();
    return message.contains('invalid_grant') ||
        message.contains('invalid refresh') ||
        (message.contains('refresh') && message.contains('expired')) ||
        (message.contains('refresh') && message.contains('revoked')) ||
        (message.contains('refresh') && message.contains('invalid token'));
  }
}
