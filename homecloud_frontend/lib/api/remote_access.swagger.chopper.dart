// dart format width=80
// Generated code

part of 'remote_access.swagger.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
final class _$RemoteAccess extends RemoteAccess {
  _$RemoteAccess([ChopperClient? client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final Type definitionType = RemoteAccess;

  @override
  Future<Response<InitiateResponse$Response>> _clientV1AuthInitiatePost({
    required String? type,
    required Code$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''This request allows a client application to start authenticating with the
service.
1. The client application must first ask the user for their email address.
2. The client application sends the user email address and some
   details about the client application to the service with this request.
3. The service replies with an opaque reference to the request.
4. The service sends an email to the user that contains a short-lived code.
5. The client application asks the user for the code they received.
6. The client application sends the reference and user code to the `token`
   API.
''',
      summary: 'Initiate client authentication',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Client"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/client/v1/auth/initiate');
    final Map<String, dynamic> $params = <String, dynamic>{'type': type};
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      parameters: $params,
      tag: swaggerMetaData,
    );
    return client.send<InitiateResponse$Response, InitiateResponse$Response>(
      $request,
    );
  }

  @override
  Future<Response<TokenResponse$Response>> _clientV1AuthRefreshGet({
    required String? refreshToken,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''This request allows a client application to renew a JWT access
token if it has expired (after 10 minutes).

The client application must send the refresh token it received
in the `token` response.
''',
      summary: 'Renew a JWT access token using a refresh token',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Client"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/client/v1/auth/refresh');
    final Map<String, dynamic> $params = <String, dynamic>{
      'refresh_token': refreshToken,
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
      tag: swaggerMetaData,
    );
    return client.send<TokenResponse$Response, TokenResponse$Response>(
      $request,
    );
  }

  @override
  Future<Response<TokenResponse$Response>> _clientV1AuthTokenPost({
    required String? type,
    required Validate$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''This request allows a client application to obtain a JWT access
token to query authenticated APIs.

The client application must send the opaque reference from the
`initiate` response and the user code received by email.
''',
      summary: 'Obtain a JWT access token',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Client"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/client/v1/auth/token');
    final Map<String, dynamic> $params = <String, dynamic>{'type': type};
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      parameters: $params,
      tag: swaggerMetaData,
    );
    return client.send<TokenResponse$Response, TokenResponse$Response>(
      $request,
    );
  }

  @override
  Future<Response<List<Device>>> _clientV1DevicesGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''This request allows a client application to obtain the list of
devices a user has access to.
''',
      summary: 'Retrieve the list of devices a user has access to',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Client"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/client/v1/devices');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<List<Device>, Device>($request);
  }

  @override
  Future<Response<DevicePaths>> _clientV1DevicesDeviceIDGet({
    required String? deviceID,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''This request allows an authenticated client application to get
information about a device.
''',
      summary: 'Get information about a device',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Client"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/client/v1/devices/${deviceID}');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<DevicePaths, DevicePaths>($request);
  }
}
