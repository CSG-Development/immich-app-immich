import 'package:chopper/chopper.dart';
import 'package:hc_device/api/api.enums.swagger.dart'
    show AuthRefreshPost$RequestBodyGrantType;
import 'package:hc_device/api/api.swagger.dart'
    show
        About,
        Api,
        AuthLoginPost$RequestBody,
        AuthLogoutPost$RequestBody,
        AuthRefreshPost$RequestBody,
        AuthResponse,
        Status,
        User;

class DeviceRepository {
  DeviceRepository(this._getApi);

  final Api Function() _getApi;

  Future<Response<AuthResponse>> loginWithPassword({
    required String email,
    required String password,
  }) {
    return _getApi().authLoginPost(
      body: AuthLoginPost$RequestBody(email: email, password: password),
    );
  }

  Future<Response<Status>> getStatus() {
    return _getApi().statusGet();
  }

  Future<Response<About>> getAbout() {
    return _getApi().aboutGet();
  }

  Future<Response<User>> getCurrentUser() {
    return _getApi().usersMeGet();
  }

  Future<Response> sendResetPasswordEmail({required String email}) {
    return _getApi().usersResetPasswordEmailPost(email: email);
  }

  Future<Response<AuthResponse>> refreshToken({
    required String refreshToken,
  }) {
    return _getApi().authRefreshPost(
      body: AuthRefreshPost$RequestBody(
        grantType: AuthRefreshPost$RequestBodyGrantType.refreshToken,
        refreshToken: refreshToken,
      ),
    );
  }

  Future<Response> logout({required String refreshToken}) {
    return _getApi().authLogoutPost(
      body: AuthLogoutPost$RequestBody(refreshToken: refreshToken),
    );
  }
}
