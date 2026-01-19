// dart format width=80
// Generated code

part of 'api.swagger.dart';

// **************************************************************************
// ChopperGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
final class _$Api extends Api {
  _$Api([ChopperClient? client]) {
    if (client == null) return;
    this.client = client;
  }

  @override
  final Type definitionType = Api;

  @override
  Future<Response<About>> _aboutGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Return information about the system',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/about');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<About, About>($request);
  }

  @override
  Future<Response<AuthResponse>> _authLoginPost({
    required AuthLoginPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Login the user with email and password',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["auth"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/auth/login');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<AuthResponse, AuthResponse>($request);
  }

  @override
  Future<Response<dynamic>> _authLogoutPost({
    required AuthLogoutPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Logout from a session, given the latest refresh token',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["auth"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/auth/logout');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<AuthResponse>> _authRefreshPost({
    required AuthRefreshPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Retrieve a new access token using the refresh token',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["auth"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/auth/refresh');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<AuthResponse, AuthResponse>($request);
  }

  @override
  Future<Response<Status>> _statusGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get the device\'s status',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["status"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/status');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<Status, Status>($request);
  }

  @override
  Future<Response<Oobe>> _statusOobeGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get the OOBE status',
      operationId: 'getStatusOOBE',
      consumes: [],
      produces: [],
      security: [],
      tags: ["status"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/status/oobe');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<Oobe, Oobe>($request);
  }
}
