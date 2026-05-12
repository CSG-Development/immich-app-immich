import 'package:chopper/chopper.dart';
import 'package:hc_device/api/remote_access.enums.swagger.dart'
    show ClientV1AuthInitiatePostType, ClientV1AuthTokenPostType;
import 'package:hc_device/api/remote_access.swagger.dart'
    show
        Code$RequestBody,
        Device,
        DevicePaths,
        InitiateResponse$Response,
        Refresh$RequestBody,
        RemoteAccess,
        TokenResponse$Response,
        Validate$RequestBody;

class RemoteRepository {
  RemoteRepository(this._getApi);

  final RemoteAccess Function() _getApi;

  Future<Response<TokenResponse$Response>> refreshToken({
    required String clientId,
    required String refreshToken,
  }) {
    return _getApi().clientV1AuthRefreshPost(
      body: Refresh$RequestBody(clientId: clientId, refreshToken: refreshToken),
    );
  }

  Future<Response<List<Device>>> getDevices() {
    return _getApi().clientV1DevicesGet();
  }

  Future<Response<DevicePaths>> getDevicePaths({
    required String deviceID,
  }) {
    return _getApi().clientV1DevicesDeviceIDGet(deviceID: deviceID);
  }

  Future<Response<InitiateResponse$Response>> initiateEmailAccess({
    required String email,
    required String clientId,
    required String clientFriendlyName,
  }) {
    return _getApi().clientV1AuthInitiatePost(
      type: ClientV1AuthInitiatePostType.email,
      body: Code$RequestBody(
        email: email,
        clientId: clientId,
        clientFriendlyName: clientFriendlyName,
      ),
    );
  }

  Future<Response<TokenResponse$Response>> validateEmailCode({
    required String code,
    required String clientId,
    required String reference,
  }) {
    return _getApi().clientV1AuthTokenPost(
      type: ClientV1AuthTokenPostType.email,
      body: Validate$RequestBody(
        code: code,
        clientId: clientId,
        reference: reference,
      ),
    );
  }
}
