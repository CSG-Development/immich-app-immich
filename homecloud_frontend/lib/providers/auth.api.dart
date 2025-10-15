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
import 'package:flutter/foundation.dart' show kDebugMode;

/// Interface for refresh logic and logout
abstract class CuratorAuthProvider {
  String? get accessToken;
  bool isRefreshRequest(Request? request);
  Future<String> refreshAccessToken();
  void logout();
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
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      // Trying to update token only 1 time
      // TODO use a better way to identify if it's a refresh request, like a custom header
      if (request.headers["accept-language"] != "42" &&
          !(_provider.isRefreshRequest(originalRequest))) {
        // Use "accept-language" to avoid to be blocked by Access-Control-Allow-Headers
        try {
          final newAccessToken = await _refreshToken();
          return applyHeaders(request, {
            HttpHeaders.authorizationHeader: 'Bearer $newAccessToken',
            // Setting a parameter to not end up in an infinite loop...
            "accept-language": '42',
          });
        } catch (e) {
          if (kDebugMode) {
            print('[Authenticator] Unable to refresh token: $e');
          }
        }
      } else if (kDebugMode) {
        print(
          '[Authenticator] Unable to refresh token, already tried or refresh token failed',
        );
      }
      // If the token cannot be refreshed, logout
      _provider.logout();
      return null;
    }
    return null;
  }

  Future<String> _refreshToken() async {
    // Completer to prevent multiple token refreshes at the same time
    if (_completer != null && !_completer!.isCompleted) {
      if (kDebugMode) {
        print('[Authenticator] Token refresh is already in progress');
      }
      return _completer!.future;
    }
    _completer = Completer<String>();
    try {
      final token = await _provider.refreshAccessToken();
      _completer!.complete(token);
    } catch (e) {
      _completer!.completeError(e);
    }
    return _completer!.future;
  }

  @override
  AuthenticationCallback? get onAuthenticationFailed => null;

  @override
  AuthenticationCallback? get onAuthenticationSuccessful => null;
}
