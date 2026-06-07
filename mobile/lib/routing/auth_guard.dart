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
  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    resolver.next(true);

    try {
      // Look in the store for an access token
      Store.get(StoreKey.accessToken);

      // Validate the access token with the server
      final res = await _apiService.authenticationApi.validateAccessToken();
      if (res == null || res.authStatus != true) {
        _log.fine('User token is invalid. Redirecting to login');
        await _redirectToLogin(router);
      }
    } on StoreKeyNotFoundException catch (_) {
      _log.warning('No access token in the store.');
      await _redirectToLogin(router);
      return;
    } on ApiException catch (e) {
      if (e.code == HttpStatus.unauthorized) {
        _log.warning("Unauthorized access token.");
        await _redirectToLogin(router);
        return;
      }
    } catch (e) {
      // Otherwise, this is not fatal, but we still log the warning
      _log.warning('Error validating access token from server: $e');
    }
  }

  Future<void> _redirectToLogin(StackRouter router) async {
    await _authService.clearLocalData();
    router.replaceAll([const LoginRoute()]);
  }
}
