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
  Future<Response<String>> _aboutCertificateGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Return the device certfificate',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/about/certificate');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<String, String>($request);
  }

  @override
  Future<Response<AdvancedConfig>> _advancedPasskeyConfigGet({
    required String passkey,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'return the current configuration and reboot',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Advanced"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/advanced/${passkey}/config');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<AdvancedConfig, AdvancedConfig>($request);
  }

  @override
  Future<Response<AdvancedConfig>> _advancedPasskeyConfigPost({
    required String passkey,
    required AdvancedConfig? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Update the current configuration',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Advanced"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/advanced/${passkey}/config');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<AdvancedConfig, AdvancedConfig>($request);
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
      security: [],
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
  Future<Response<String>> _diagGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Return the diagnostic',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/diag');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<String, String>($request);
  }

  @override
  Future<Response<List<NetworkInterface>>> _networkInterfacesGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Allows listing network interfaces',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Network"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/network/interfaces');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<List<NetworkInterface>, NetworkInterface>($request);
  }

  @override
  Future<Response<dynamic>> _networkInterfacesInterfacePut({
    required String interface,
    required InterfaceConfig? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Allows configuring a network interface',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Network"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/network/interfaces/${interface}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<OpenIDConfigurationResponse>>
  _oauthWellKnownOpenidConfigurationGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'OpenID Configuration',
      operationId: 'openidConfiguration',
      consumes: [],
      produces: [],
      security: [],
      tags: ["auth"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oauth/.well-known/openid-configuration');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client
        .send<OpenIDConfigurationResponse, OpenIDConfigurationResponse>(
          $request,
        );
  }

  @override
  Future<Response<AuthorizeResponse>> _oauthAuthorizePost({
    required AuthorizeRequest? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'OAuth Authorize',
      operationId: 'oauthAuthorize',
      consumes: [],
      produces: [],
      security: [],
      tags: ["auth"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oauth/authorize');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<AuthorizeResponse, AuthorizeResponse>($request);
  }

  @override
  Future<Response<JwksResponse>> _oauthJwksGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'OAuth JWKS',
      operationId: 'oauthJwks',
      consumes: [],
      produces: [],
      security: [],
      tags: ["auth"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oauth/jwks');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<JwksResponse, JwksResponse>($request);
  }

  @override
  Future<Response<dynamic>> _buttonDelete({
    required ButtonAction? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Clear button status during OOBE',
      operationId: 'DeleteButton',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/button');
    final $body = body;
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<ButtonStatus>> _oobeButtonGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Check if button is pressed during OOBE',
      operationId: 'GetOOBEButton',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oobe/button');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<ButtonStatus, ButtonStatus>($request);
  }

  @override
  Future<Response<dynamic>> _oobeButtonPost({
    required ButtonAction? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Wait for button to be pressed during OOBE',
      operationId: 'PostOOBEButton',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oobe/button');
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
  Future<Response<dynamic>> _oobeOwnerPost({
    required OobeOwnerPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Create the owner user',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oobe/owner');
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
  Future<Response<dynamic>> _oobeOwnerPut({
    required OobeOwnerPut$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Confirm and create the owner user',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oobe/owner');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _oobePowerPost({
    required OobePowerPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Power off or reboot the device',
      operationId: 'PostOOBEPower',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/oobe/power');
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
  Future<Response<dynamic>> _powerPost({
    required PowerPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'To power off or reboot the device',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/power');
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
  Future<Response<DeviceConfiguration>> _prodConfigurationGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Production Configuration',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/prod/configuration');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<DeviceConfiguration, DeviceConfiguration>($request);
  }

  @override
  Future<Response<dynamic>> _resetPost({
    required ResetPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'To reset the device',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/reset');
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
  Future<Response<dynamic>> _setupPost({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Start the system initial setup',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/setup');
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _smtpDelete({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary:
          'Delete custom SMTP configuration and revert to Seagate mail service',
      operationId: 'DeleteSMTP',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/smtp');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<SMTPConfig>> _smtpGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get the SMTP relay current configuration',
      operationId: 'GetSMTP',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/smtp');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<SMTPConfig, SMTPConfig>($request);
  }

  @override
  Future<Response<dynamic>> _smtpPost({
    required SMTPConfig? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Set the current SMTP relay configuration',
      operationId: 'PostSMTP',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/smtp');
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

  @override
  Future<Response<StorageStats>> _storageGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''Returns a comprehensive storage snapshot including global disk usage,
SMART health data, per-application breakdown, and per-user breakdown.
Requires admin scope.
''',
      summary: 'Get full storage statistics (admin only)',
      operationId: 'GetStorage',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["storage"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/storage');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<StorageStats, StorageStats>($request);
  }

  @override
  Future<Response<UserStorageStats>> _storageMeGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          '''Returns global disk capacity information and the requesting user\'s
personal storage usage across all applications.
Requires user or admin scope.
''',
      summary: 'Get personal storage usage (authenticated user)',
      operationId: 'GetStorageMe',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["storage"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/storage/me');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<UserStorageStats, UserStorageStats>($request);
  }

  @override
  Future<Response<TimeConfig>> _timeGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Returns the system\'s current time configuration',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/time');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<TimeConfig, TimeConfig>($request);
  }

  @override
  Future<Response<dynamic>> _timePost({
    required TimeConfig? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: 'Configures the system\'s time',
      summary: '',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/time');
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
  Future<Response<List<Update>>> _updateGet({
    String? type,
    bool? force,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Return available updates',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/update');
    final Map<String, dynamic> $params = <String, dynamic>{
      'type': type,
      'force': force,
    };
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      parameters: $params,
      tag: swaggerMetaData,
    );
    return client.send<List<Update>, Update>($request);
  }

  @override
  Future<Response<UpdateInfo>> _updatePost({
    required Update? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Apply update',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/update');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<UpdateInfo, UpdateInfo>($request);
  }

  @override
  Future<Response<UpdateProgress>> _updateProgressGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Return the progress of the current update',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/update/progress');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<UpdateProgress, UpdateProgress>($request);
  }

  @override
  Future<Response<UpdateInfo>> _updateUploadPost({
    required Object? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Start an update using the uploaded file',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["Support"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/update/upload');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<UpdateInfo, UpdateInfo>($request);
  }

  @override
  Future<Response<List<User>>> _usersGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'List users',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<List<User>, User>($request);
  }

  @override
  Future<Response<dynamic>> _usersIdDelete({
    required String id,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Delete the user',
      operationId: 'deleteUsersID',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/${id}');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<User>> _usersIdGet({
    required String id,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get the user\'s information',
      operationId: 'getUsersID',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/${id}');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<User, User>($request);
  }

  @override
  Future<Response<dynamic>> _usersIdPut({
    required String id,
    required UsersIdPut$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Update the user\'s information',
      operationId: 'putUsersID',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/${id}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _usersChangeEmailIdPost({
    required String id,
    required UsersChangeEmailIdPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          'Initiates an email change request and sends a confirmation code to the new email address',
      summary: 'Request an email change for a user',
      operationId: 'PostUsersChangeEmailID',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/change_email/${id}');
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
  Future<Response<dynamic>> _usersChangeEmailIdPut({
    required String id,
    required UsersChangeEmailIdPut$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description:
          'Validates the confirmation code and updates the user\'s email address',
      summary: 'Confirm an email change with confirmation code',
      operationId: 'PutUsersChangeEmailID',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/change_email/${id}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<List<Invite>>> _usersInvitesGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'List pending user invites',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/invites');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<List<Invite>, Invite>($request);
  }

  @override
  Future<Response<dynamic>> _usersInvitesEmailDelete({
    required String email,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Remove the invite for the given email',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/invites/${email}');
    final Request $request = Request(
      'DELETE',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _usersInvitesEmailPost({
    required String email,
    required UsersInvitesEmailPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Create a new user invite',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/invites/${email}');
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
  Future<Response<dynamic>> _usersInvitesEmailPut({
    required String email,
    required UsersInvitesEmailPut$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Confirm an invite and create the user',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/invites/${email}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<User>> _usersMeGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get my own user information',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/me');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<User, User>($request);
  }

  @override
  Future<Response<dynamic>> _usersMePut({
    required UsersMePut$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Update my own user information',
      operationId: '',
      consumes: [],
      produces: [],
      security: ["BearerAuth"],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/me');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _usersResetPasswordEmailPost({
    required String email,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Send a reset password request',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/reset_password/${email}');
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _usersResetPasswordEmailPut({
    required String email,
    required UsersResetPasswordEmailPut$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Confirm the password reset',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/reset_password/${email}');
    final $body = body;
    final Request $request = Request(
      'PUT',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<dynamic, dynamic>($request);
  }

  @override
  Future<Response<dynamic>> _usersTransferOwnerPost({
    required UsersTransferOwnerPost$RequestBody? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Give ownership to another user',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/users/transfer_owner');
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
  Future<Response<WifiConfig>> _wifiGet({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get the current Wi-Fi configuration',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/wifi');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<WifiConfig, WifiConfig>($request);
  }

  @override
  Future<Response<WifiConfig>> _wifiPost({
    required WifiConfig? body,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Set the current Wi-Fi configuration',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/wifi');
    final $body = body;
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      body: $body,
      tag: swaggerMetaData,
    );
    return client.send<WifiConfig, WifiConfig>($request);
  }

  @override
  Future<Response<List<WifiNetwork>>> _wifiScanPost({
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Set the current Wi-Fi configuration',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/wifi/scan');
    final Request $request = Request(
      'POST',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<List<WifiNetwork>, WifiNetwork>($request);
  }

  @override
  Future<Response<WifiNetwork>> _wifiScanSsidGet({
    required String ssid,
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Search for Wi-Fi networks with the specified SSID',
      operationId: 'GetWifiScanSSID',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  }) {
    final Uri $url = Uri.parse('/wifi/scan/${ssid}');
    final Request $request = Request(
      'GET',
      $url,
      client.baseUrl,
      tag: swaggerMetaData,
    );
    return client.send<WifiNetwork, WifiNetwork>($request);
  }
}
