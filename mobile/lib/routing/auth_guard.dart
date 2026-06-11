import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class AuthGuard extends AutoRouteGuard {
  AuthGuard(this._apiService);

  final ApiService _apiService;
  final _log = Logger("AuthGuard");
  static const Duration _validationRetryDelay = Duration(milliseconds: 450);

  static int _validationGeneration = 0;

  String get _authPathContext =>
      'store=${Store.tryGet(StoreKey.serverEndpoint)} api=${_apiService.apiClient.basePath} switching=${_apiService.isEndpointSwitchInProgress}';

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    resolver.next(true);

    final generation = ++_validationGeneration;

    try {
      // Look in the store for an access token
      Store.get(StoreKey.accessToken);

      if (_apiService.isEndpointSwitchInProgress) {
        _log.fine('[auth-path] validation skipped $_authPathContext');
        return;
      }

      // Validate the access token with the server
      final res = await _apiService.authenticationApi.validateAccessToken();
      if (generation != _validationGeneration) {
        return;
      }

      if (res != null && res.authStatus != true) {
        final recovered = await _retryValidationAfterFailure(generation, reason: 'auth_status_false');
        if (!recovered) {
          _log.fine('User token is invalid. Redirecting to login');
          _redirectToLogin(router, reason: 'validate_access_token_false');
        }
      }
    } on StoreKeyNotFoundException catch (_) {
      if (generation != _validationGeneration) {
        return;
      }
      _log.warning('No access token in the store.');
      _redirectToLogin(router, reason: 'missing_access_token_in_store');
      return;
    } on ApiException catch (e) {
      if (generation != _validationGeneration) {
        return;
      }
      if (e.code == HttpStatus.unauthorized) {
        final recovered = await _retryValidationAfterFailure(generation, reason: 'validate_access_token_401');
        if (!recovered) {
          _log.warning("Unauthorized access token.");
          _redirectToLogin(router, reason: 'validate_access_token_401');
        }
        return;
      }
    } catch (e) {
      _log.warning('Error validating access token from server: $e');
    }
  }

  Future<bool> _retryValidationAfterFailure(
    int generation, {
    required String reason,
  }) async {
    if (generation != _validationGeneration) {
      return true;
    }
    _log.info(
      'Auth validation retry scheduled reason=$reason endpointSwitchInProgress=${_apiService.isEndpointSwitchInProgress}',
    );
    await _apiService.waitForEndpointSwitchToSettle();
    if (generation != _validationGeneration) {
      return true;
    }
    await Future<void>.delayed(_validationRetryDelay);
    if (generation != _validationGeneration) {
      return true;
    }
    try {
      final retry = await _apiService.authenticationApi.validateAccessToken();
      if (generation != _validationGeneration) {
        return true;
      }
      final success = retry == null || retry.authStatus == true;
      _log.info('Auth validation retry result reason=$reason success=$success');
      return success;
    } on ApiException catch (e) {
      if (generation != _validationGeneration) {
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

  void _redirectToLogin(StackRouter router, {required String reason}) {
    if (router.current.name == LoginRoute.name) {
      _log.info('Auth redirect skipped: already on login route reason=$reason');
      return;
    }
    _log.fine('[auth-path] redirect context reason=$reason $_authPathContext');
    _log.warning(
      'Auth redirect to login reason=$reason currentRoute=${router.current.name} endpointSwitchInProgress=${_apiService.isEndpointSwitchInProgress}',
    );
    unawaited(router.replaceAll([const LoginRoute()]));
  }
}
