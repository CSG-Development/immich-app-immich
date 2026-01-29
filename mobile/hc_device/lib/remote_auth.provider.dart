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

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'api/remote_access.swagger.dart';
import 'providers/device.provider.dart';
import 'providers/hcdevice.provider.dart';
import 'providers/remote.provider.dart';
import 'utils.dart' as hc_utils;

/// High-level error types for the remote authentication flow.
enum RemoteAuthError {
  invalidCode,
  expiredCode,
  network,
  server,
  unknown,
  notAllowed,
  tooManyRequests
}

class RemoteAuthState {
  final bool isInitiating;
  final bool isValidating;
  final RemoteAuthError? error;
  final String? errorMessage;
  final bool codeExpired;

  const RemoteAuthState({
    this.isInitiating = false,
    this.isValidating = false,
    this.error,
    this.errorMessage,
    this.codeExpired = false,
  });

  RemoteAuthState copyWith({
    bool? isInitiating,
    bool? isValidating,
    RemoteAuthError? error,
    String? errorMessage,
    bool? codeExpired,
  }) {
    return RemoteAuthState(
      isInitiating: isInitiating ?? this.isInitiating,
      isValidating: isValidating ?? this.isValidating,
      error: error,
      errorMessage: errorMessage,
      codeExpired: codeExpired ?? this.codeExpired,
    );
  }
}

/// Controller that encapsulates the Remote Access authentication flow
/// (initiate by email and validate code) for host apps.
final remoteAuthProvider =
    ChangeNotifierProvider<RemoteAuthController>((ref) {
  final remote = ref.read(remoteProvider);
  final device = ref.read(deviceProvider);
  return RemoteAuthController(remote, device);
});

class RemoteAuthController extends ChangeNotifier {
  final RemoteProvider _remoteProvider;
  final DeviceProvider _deviceProvider;

  bool _isDisposed = false;

  RemoteAuthState _state = const RemoteAuthState();
  String? _lastEmail;
  String? _lastClientFriendlyName;

  RemoteAuthController(this._remoteProvider, this._deviceProvider);

  RemoteAuthState get state => _state;


  void _setState(RemoteAuthState newState) {
    if (_isDisposed) return;
    _state = newState;
    
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  /// Initiate remote access authentication by sending a code to the given email.
  Future<void> initiate({
    required String email,
    required String clientFriendlyName,
  }) async {
    if (_state.isInitiating) return;

    // Clear any previous authentication of remote access server.
    _remoteProvider.logout();

    // Save email in device provider to pre-fill next time.
    _deviceProvider.setHost(login: email);

    _lastEmail = email;
    _lastClientFriendlyName = clientFriendlyName;
    _setState(
      _state.copyWith(
        isInitiating: true,
        error: null,
        errorMessage: null,
        codeExpired: false,
      ),
    );

    try {
      final response = await _remoteProvider.api.clientV1AuthInitiatePost(
        type: ClientV1AuthInitiatePostType.email,
        body: Code$RequestBody(
          email: email,
          clientId: _remoteProvider.clientId,
          clientFriendlyName: clientFriendlyName,
        ),
      );

      if (response.isSuccessful) {

        if (kDebugMode) {
          debugPrint(
            "[RemoteAuth] Remote access initiated for email: "
            "$email, response: ${response.body}",
          );
        }

        _remoteProvider.reference = response.body?.reference;
        _setState(
          _state.copyWith(
            isInitiating: false,
            error: null,
            errorMessage: null,
            codeExpired: false,
          ),
        );
      } else {
        final message = hc_utils.extractErrorMessage(response);
        if (kDebugMode) {
          debugPrint(
            "[RemoteAuth] Initiate error: $message",
          );
          debugPrint(
            "[RemoteAuth] Initiate status code: ${response.statusCode}",
          );
        }
        switch (response.statusCode) {
          case 401:
          case 403:
            _setState(
              _state.copyWith(isInitiating: false, error: RemoteAuthError.notAllowed),
            );
            break;
          case 429:
            _setState(
              _state.copyWith(isInitiating: false, error: RemoteAuthError.tooManyRequests),
            );
            break;
          case 500:
            _setState(
              _state.copyWith(isInitiating: false, error: RemoteAuthError.server),
            );
            break;
          default:
            _setState(
              _state.copyWith(isInitiating: false, error: RemoteAuthError.unknown, errorMessage: message),
            );
            break;
        }
      }
    } catch (error) {
      final message = hc_utils.extractErrorMessage(error);
      if (kDebugMode) {
        debugPrint(
          "[RemoteAuth] Initiate network error: $message",
        );
      }
      _setState(
        _state.copyWith(
          isInitiating: false,
          error: RemoteAuthError.network,
          errorMessage: message,
        ),
      );
    }
  }

  /// Re-initiate remote access using the last used email and client name.
  Future<void> resendLast() async {
    if (_lastEmail == null || _lastClientFriendlyName == null) {
      return;
    }
    await initiate(
      email: _lastEmail!,
      clientFriendlyName: _lastClientFriendlyName!,
    );
  }

  /// Validate the remote access code and get access and refresh tokens.
  Future<bool> validateCode(String code) async {
    if (_state.isValidating || _state.isInitiating) {
      return false;
    }

    _setState(
      _state.copyWith(
        isValidating: true,
        error: null,
        errorMessage: null,
        codeExpired: false,
      ),
    );

    try {
      final response = await _remoteProvider.api.clientV1AuthTokenPost(
        type: ClientV1AuthTokenPostType.email,
        body: Validate$RequestBody(
          clientId: _remoteProvider.clientId,
          code: code,
          reference: _remoteProvider.reference!,
        ),
      );

      if (kDebugMode) {
        debugPrint(
          "[RemoteAuth] Code validation response: "
          "${response.isSuccessful}, body: ${response.body}",
        );
      }

      if (response.isSuccessful) {
        _remoteProvider.setAuthToken(auth: response.body!);
        _setState(
          _state.copyWith(
            isValidating: false,
            error: null,
            errorMessage: null,
            codeExpired: false,
          ),
        );
        return true;
      } else {
        final rawMessage = hc_utils.extractErrorMessage(response);
        RemoteAuthError errorType = RemoteAuthError.server;
        bool expired = false;
        String message = rawMessage;

        if (message.toLowerCase().contains('invalid')) {
          errorType = RemoteAuthError.invalidCode;
        } else if (message.toLowerCase().contains('expired')) {
          errorType = RemoteAuthError.expiredCode;
          expired = true;
        }

        _setState(
          _state.copyWith(
            isValidating: false,
            error: errorType,
            errorMessage: message,
            codeExpired: expired,
          ),
        );
        return false;
      }
    } catch (error) {
      final message = hc_utils.extractErrorMessage(error);
      if (kDebugMode) {
        debugPrint(
          "[RemoteAuth] Code validation network error: $message",
        );
      }
      _setState(
        _state.copyWith(
          isValidating: false,
          error: RemoteAuthError.network,
          errorMessage: message,
          codeExpired: false,
        ),
      );
      return false;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    
    _state = const RemoteAuthState();
    
    super.dispose();
  }
}


