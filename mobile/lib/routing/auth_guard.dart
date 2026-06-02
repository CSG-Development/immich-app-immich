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

  static int _validationGeneration = 0;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    resolver.next(true);

    final generation = ++_validationGeneration;

    try {
      // Look in the store for an access token
      Store.get(StoreKey.accessToken);

      if (_apiService.isEndpointSwitchInProgress) {
        return;
      }

      // Validate the access token with the server
      final res = await _apiService.authenticationApi.validateAccessToken();
      if (generation != _validationGeneration) {
        return;
      }

      if (res != null && res.authStatus != true) {
        _log.fine('User token is invalid. Redirecting to login');
        _redirectToLogin(router);
      }
    } on StoreKeyNotFoundException catch (_) {
      if (generation != _validationGeneration) {
        return;
      }
      _log.warning('No access token in the store.');
      _redirectToLogin(router);
      return;
    } on ApiException catch (e) {
      if (generation != _validationGeneration) {
        return;
      }
      if (e.code == HttpStatus.unauthorized) {
        _log.warning("Unauthorized access token.");
        _redirectToLogin(router);
        return;
      }
    } catch (e) {
      _log.warning('Error validating access token from server: $e');
    }
  }

  void _redirectToLogin(StackRouter router) {
    if (router.current.name == LoginRoute.name) {
      return;
    }
    unawaited(router.replaceAll([const LoginRoute()]));
  }
}
