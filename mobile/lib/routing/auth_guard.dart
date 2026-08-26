import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/auth.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class AuthGuard extends AutoRouteGuard {
  AuthGuard(this._apiService, this._authService);

  final ApiService _apiService;
  final AuthService _authService;
  final _log = Logger("AuthGuard");
  static const Duration _validationRetryDelay = Duration(milliseconds: 450);
  bool _validateInFlight = false;

  String get _authPathContext =>
      'store=${Store.tryGet(StoreKey.serverEndpoint)} api=${_apiService.apiClient.basePath} switching=${_apiService.isEndpointSwitchInProgress}';

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    try {
      Store.get(StoreKey.accessToken);
    } on StoreKeyNotFoundException catch (_) {
      _log.warning('No access token in the store.');
      resolver.next(false);
      _redirectToLogin(router, reason: 'missing_access_token_in_store');
      return;
    }

    resolver.next(true);
    unawaited(_validateAccessTokenInBackground(router));
  }

  Future<void> _validateAccessTokenInBackground(StackRouter router) async {
    if (_apiService.isEndpointSwitchInProgress) {
      _log.fine('[auth-path] validation skipped $_authPathContext');
      return;
    }
    if (_validateInFlight) {
      return;
    }
    final token = Store.tryGet(StoreKey.accessToken);
    if (token == null) {
      return;
    }
    _validateInFlight = true;
    try {
      final res = await _apiService.authenticationApi.validateAccessToken();
      if (Store.tryGet(StoreKey.accessToken) != token) {
        return;
      }
      if (res != null && res.authStatus != true) {
        final recovered = await _retryValidationAfterFailure(token, reason: 'auth_status_false');
        if (!recovered) {
          if (Store.tryGet(StoreKey.accessToken) != token) {
            return;
          }
          _log.fine('User token is invalid. Redirecting to login');
          _redirectToLogin(router, reason: 'validate_access_token_false', clearLocalData: true);
        }
      }
    } on ApiException catch (e) {
      if (e.code != HttpStatus.unauthorized) {
        return;
      }
      if (Store.tryGet(StoreKey.accessToken) != token) {
        return;
      }
      final recovered = await _retryValidationAfterFailure(token, reason: 'validate_access_token_401');
      if (!recovered) {
        if (Store.tryGet(StoreKey.accessToken) != token) {
          return;
        }
        _log.warning("Unauthorized access token.");
        _redirectToLogin(router, reason: 'validate_access_token_401', clearLocalData: true);
      }
    } catch (e) {
      _log.warning('Error validating access token from server: $e');
    } finally {
      _validateInFlight = false;
    }
  }

  Future<bool> _retryValidationAfterFailure(
    String token, {
    required String reason,
  }) async {
    _log.info(
      'Auth validation retry scheduled reason=$reason endpointSwitchInProgress=${_apiService.isEndpointSwitchInProgress}',
    );
    await _apiService.waitForEndpointSwitchToSettle();
    if (Store.tryGet(StoreKey.accessToken) != token) {
      return true;
    }
    await Future<void>.delayed(_validationRetryDelay);
    if (Store.tryGet(StoreKey.accessToken) != token) {
      return true;
    }
    try {
      final retry = await _apiService.authenticationApi.validateAccessToken();
      if (Store.tryGet(StoreKey.accessToken) != token) {
        return true;
      }
      final success = retry == null || retry.authStatus == true;
      _log.info('Auth validation retry result reason=$reason success=$success');
      return success;
    } on ApiException catch (e) {
      if (Store.tryGet(StoreKey.accessToken) != token) {
        return true;
      }
      _log.warning(
        'Auth validation retry failed reason=$reason statusCode=${e.code}',
      );
      return false;
    } catch (e) {
      _log.warning('Auth validation retry failed reason=$reason error=$e');
      return false;
    }
  }

  void _redirectToLogin(
    StackRouter router, {
    required String reason,
    bool clearLocalData = false,
  }) {
    if (router.current.name == LoginRoute.name) {
      _log.info('Auth redirect skipped: already on login route reason=$reason');
      return;
    }
    _log.fine('[auth-path] redirect context reason=$reason $_authPathContext');
    _log.warning(
      'Auth redirect to login reason=$reason currentRoute=${router.current.name} endpointSwitchInProgress=${_apiService.isEndpointSwitchInProgress}',
    );
    final navigation = router.replaceAll([const LoginRoute()]);
    if (clearLocalData) {
      unawaited(navigation.then((_) => _authService.clearLocalData()));
    } else {
      unawaited(navigation);
    }
  }
}
