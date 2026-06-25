import 'dart:async' show TimeoutException;
import 'dart:io' show HandshakeException, HttpStatus, SocketException;

import 'package:chopper/chopper.dart';

/// Log-friendly reason codes for RA refresh failures.
abstract final class RefreshFailureReason {
  static const missingToken = 'missing_refresh_token';
  static const raInvalidToken = 'ra_invalid_refresh_token';
  static const tokenRejected = 'refresh_token_rejected';
  static const network = 'network_error';
  static const server = 'server_error';
  static const alreadyAttempted = 'refresh_already_attempted';
  static const unknown = 'unknown';
}

class RefreshFailureInfo {
  const RefreshFailureInfo({
    required this.reason,
    required this.confident,
    this.detail,
    this.statusCode,
  });

  final String reason;
  final bool confident;
  final String? detail;
  final int? statusCode;

  String get logSuffix =>
      'reason=$reason confident=$confident statusCode=${statusCode ?? '-'} detail=${detail ?? '-'}';
}

class RefreshFailureClassifier {
  static RefreshFailureInfo describe(Object error) {
    if (error is StateError) {
      final message = error.message.toLowerCase();
      if (message.contains('refresh token is missing')) {
        return RefreshFailureInfo(
          reason: RefreshFailureReason.missingToken,
          confident: true,
          detail: error.message,
        );
      }
    }

    if (error is Response) {
      final status = error.statusCode;
      final payload = _payload(error);
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        if (_hasInvalidRefreshHint(payload)) {
          return RefreshFailureInfo(
            reason: RefreshFailureReason.raInvalidToken,
            confident: true,
            statusCode: status,
            detail: _trimDetail(payload),
          );
        }
        return RefreshFailureInfo(
          reason: RefreshFailureReason.tokenRejected,
          confident: true,
          statusCode: status,
          detail: _trimDetail(payload),
        );
      }
      if (status == HttpStatus.badRequest && _hasInvalidRefreshHint(payload)) {
        return RefreshFailureInfo(
          reason: RefreshFailureReason.raInvalidToken,
          confident: true,
          statusCode: status,
          detail: _trimDetail(payload),
        );
      }
      if (status >= 500) {
        return RefreshFailureInfo(
          reason: RefreshFailureReason.server,
          confident: false,
          statusCode: status,
          detail: _trimDetail(payload),
        );
      }
      return RefreshFailureInfo(
        reason: RefreshFailureReason.unknown,
        confident: false,
        statusCode: status,
        detail: _trimDetail(payload),
      );
    }

    if (error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException) {
      return RefreshFailureInfo(
        reason: RefreshFailureReason.network,
        confident: false,
        detail: error.toString(),
      );
    }

    final message = error.toString();
    final normalized = message.toLowerCase();
    if (normalized.contains('socketexception') ||
        normalized.contains('connection refused') ||
        normalized.contains('connection closed') ||
        normalized.contains('connection reset') ||
        normalized.contains('failed host lookup') ||
        normalized.contains('network is unreachable') ||
        normalized.contains('timed out') ||
        normalized.contains('handshakeexception') ||
        normalized.contains('clientexception')) {
      return RefreshFailureInfo(
        reason: RefreshFailureReason.network,
        confident: false,
        detail: _trimDetail(message),
      );
    }

    if (_hasInvalidRefreshHint(normalized)) {
      return RefreshFailureInfo(
        reason: RefreshFailureReason.raInvalidToken,
        confident: true,
        detail: _trimDetail(message),
      );
    }

    if ((normalized.contains('401') || normalized.contains('403')) &&
        normalized.contains('unauthorized')) {
      return RefreshFailureInfo(
        reason: RefreshFailureReason.tokenRejected,
        confident: false,
        detail: _trimDetail(message),
      );
    }

    return RefreshFailureInfo(
      reason: RefreshFailureReason.unknown,
      confident: false,
      detail: _trimDetail(message),
    );
  }

  static RefreshFailureInfo alreadyAttempted() => const RefreshFailureInfo(
        reason: RefreshFailureReason.alreadyAttempted,
        confident: true,
        detail: 'Token refresh was already attempted for this request',
      );

  static bool shouldLogoutOnRefreshFailure(Object error) {
    if (error is Response) {
      final status = error.statusCode;
      if (status == HttpStatus.unauthorized || status == HttpStatus.forbidden) {
        return true;
      }
      if (status == HttpStatus.badRequest) {
        return _hasInvalidRefreshHint(_payload(error));
      }
      return false;
    }

    if (error is SocketException ||
        error is HandshakeException ||
        error is TimeoutException) {
      return false;
    }

    final message = error.toString().toLowerCase();
    return (message.contains('401') && message.contains('unauthorized')) ||
        (message.contains('403') && message.contains('forbidden')) ||
        _hasInvalidRefreshHint(message);
  }

  static String _payload(Response response) =>
      '${response.error ?? ''} ${response.body ?? ''}';

  static bool _hasInvalidRefreshHint(String text) {
    final message = text.toLowerCase();
    return message.contains('invalid_grant') ||
        message.contains('invalid refresh') ||
        (message.contains('refresh') && message.contains('expired')) ||
        (message.contains('refresh') && message.contains('revoked')) ||
        (message.contains('refresh') && message.contains('invalid token'));
  }

  static String? _trimDetail(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.length <= 200 ? trimmed : '${trimmed.substring(0, 200)}...';
  }
}
