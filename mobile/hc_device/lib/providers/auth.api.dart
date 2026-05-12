//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2025 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//   Any use, modification, duplication, derivation, distribution or disclosure
//   of this code, for any reason, not expressly authorized is prohibited.
//   All other rights are expressly reserved by Seagate Technology LLC.
//

import 'dart:async';
import 'dart:io';

import 'package:chopper/chopper.dart';
import 'package:hc_device/services/logger_service.dart';

/// Interface for refresh logic and logout
abstract class CuratorAuthProvider {
  String? get accessToken;
  bool get isAuthenticated;
  bool isRefreshRequest(Request? request);
  Future<String> refreshAccessToken();
  Future<void> logOut({bool notify});

  /// Override when refresh failures should force logout.
  bool shouldLogoutOnRefreshFailure(Object error) => false;
}

/// Generic interceptor for adding the Authorization header
class CuratorInterceptor implements Interceptor {
  final CuratorAuthProvider _provider;
  CuratorInterceptor(this._provider);

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(
    Chain<BodyType> chain,
  ) async {
    // If no token or it's a refresh request, just proceed
    if (_provider.accessToken == null ||
        _provider.isRefreshRequest(chain.request)) {
      return chain.proceed(chain.request);
    }
    // Add the Authorization header
    final request = applyHeader(
      chain.request,
      HttpHeaders.authorizationHeader,
      'Bearer ${_provider.accessToken}',
      // Do not override existing header (like in the case of a retry)
      override: false,
    );
    return chain.proceed(request);
  }
}

/// Generic Authenticator for handling 401 and token refresh
class CuratorAuthenticator implements Authenticator {
  static const String _refreshRetryMarkerHeader = 'accept-language';
  static const String _refreshRetryMarkerValue = '42';

  final CuratorAuthProvider _provider;
  Completer<String>? _completer;

  CuratorAuthenticator(this._provider);

  @override
  FutureOr<Request?> authenticate(
    Request request,
    Response response, [
    Request? originalRequest,
  ]) async {
    // Catch if the response is unauthorized (401) or forbidden (403)
    // Only try to refresh if the user is authenticated and if we haven't already tried to refresh for this request
    if (_provider.isAuthenticated &&
        (response.statusCode == HttpStatus.unauthorized ||
            response.statusCode == HttpStatus.forbidden)) {
      // Trying to update token only 1 time
      // TODO use a better way to identify if it's a refresh request, like a custom header
      if (request.headers[_refreshRetryMarkerHeader] != _refreshRetryMarkerValue &&
          !(_provider.isRefreshRequest(originalRequest))) {
        // Use accept-language to avoid being blocked by Access-Control-Allow-Headers.
        try {
          final newAccessToken = await _refreshToken();
          return applyHeaders(request, {
            HttpHeaders.authorizationHeader: 'Bearer $newAccessToken',
            // Retry marker to avoid infinite refresh/retry loops.
            _refreshRetryMarkerHeader: _refreshRetryMarkerValue,
          });
        } catch (e) {
          logger.error('[Auth] Unable to refresh token', e);
          if (_provider.shouldLogoutOnRefreshFailure(e)) {
            await _provider.logOut(notify: true);
          }
        }
      } else {
        logger.warning('[Auth] Unable to refresh token (already attempted or failed)');
        await _provider.logOut(notify: true);
      }
      return null;
    }
    return null;
  }

  Future<String> _refreshToken() async {
    // Completer to prevent multiple token refreshes at the same time
    if (_completer != null && !_completer!.isCompleted) {
      logger.debug('[Auth] Token refresh already in progress');
      return _completer!.future;
    }
    _completer = Completer<String>();
    try {
      final token = await _provider.refreshAccessToken();
      _completer!.complete(token);
      _completer = null; // Reset for next refresh cycle
      return token;
    } catch (e) {
      logger.error('[Auth] Automatic token refresh failed', e);
      _completer!.completeError(e);
      _completer = null; // Reset so next request can retry
      rethrow;
    }
  }

  @override
  AuthenticationCallback? get onAuthenticationFailed => null;

  @override
  AuthenticationCallback? get onAuthenticationSuccessful => null;
}
