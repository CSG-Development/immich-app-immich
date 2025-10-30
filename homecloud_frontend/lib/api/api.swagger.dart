// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element_parameter

import 'package:json_annotation/json_annotation.dart';
import 'package:json_annotation/json_annotation.dart' as json;
import 'package:collection/collection.dart';
import 'dart:convert';

import 'package:chopper/chopper.dart';

import 'client_mapping.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show MultipartFile;
import 'package:chopper/chopper.dart' as chopper;
import 'api.enums.swagger.dart' as enums;
import 'api.metadata.swagger.dart';
export 'api.enums.swagger.dart';

part 'api.swagger.chopper.dart';
part 'api.swagger.g.dart';

// **************************************************************************
// SwaggerChopperGenerator
// **************************************************************************

@ChopperApi()
abstract class Api extends ChopperService {
  static Api create({
    ChopperClient? client,
    http.Client? httpClient,
    Authenticator? authenticator,
    ErrorConverter? errorConverter,
    Converter? converter,
    Uri? baseUrl,
    List<Interceptor>? interceptors,
  }) {
    if (client != null) {
      return _$Api(client);
    }

    final newClient = ChopperClient(
      services: [_$Api()],
      converter: converter ?? $JsonSerializableConverter(),
      interceptors: interceptors ?? [],
      client: httpClient,
      authenticator: authenticator,
      errorConverter: errorConverter,
      baseUrl: baseUrl ?? Uri.parse('http://'),
    );
    return _$Api(newClient);
  }

  ///Return information about the system
  Future<chopper.Response<About>> aboutGet() {
    generatedMapping.putIfAbsent(About, () => About.fromJsonFactory);

    return _aboutGet();
  }

  ///Return information about the system
  @GET(path: '/about')
  Future<chopper.Response<About>> _aboutGet({
    @chopper.Tag()
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
  });

  ///Return the device certfificate
  Future<chopper.Response<String>> aboutCertificateGet() {
    return _aboutCertificateGet();
  }

  ///Return the device certfificate
  @GET(path: '/about/certificate')
  Future<chopper.Response<String>> _aboutCertificateGet({
    @chopper.Tag()
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
  });

  ///Return configuration information about the system
  Future<chopper.Response<DeviceConfiguration>> aboutConfigurationGet() {
    generatedMapping.putIfAbsent(
      DeviceConfiguration,
      () => DeviceConfiguration.fromJsonFactory,
    );

    return _aboutConfigurationGet();
  }

  ///Return configuration information about the system
  @GET(path: '/about/configuration')
  Future<chopper.Response<DeviceConfiguration>> _aboutConfigurationGet({
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Return configuration information about the system',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  });

  ///return the current configuration and reboot
  Future<chopper.Response<AdvancedConfig>> advancedPasskeyConfigGet({
    required String? passkey,
  }) {
    generatedMapping.putIfAbsent(
      AdvancedConfig,
      () => AdvancedConfig.fromJsonFactory,
    );

    return _advancedPasskeyConfigGet(passkey: passkey);
  }

  ///return the current configuration and reboot
  @GET(path: '/advanced/{passkey}/config')
  Future<chopper.Response<AdvancedConfig>> _advancedPasskeyConfigGet({
    @Path('passkey') required String? passkey,
    @chopper.Tag()
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
  });

  ///Update the current configuration
  Future<chopper.Response<AdvancedConfig>> advancedPasskeyConfigPost({
    required String? passkey,
    required AdvancedConfig? body,
  }) {
    generatedMapping.putIfAbsent(
      AdvancedConfig,
      () => AdvancedConfig.fromJsonFactory,
    );

    return _advancedPasskeyConfigPost(passkey: passkey, body: body);
  }

  ///Update the current configuration
  @POST(path: '/advanced/{passkey}/config', optionalBody: true)
  Future<chopper.Response<AdvancedConfig>> _advancedPasskeyConfigPost({
    @Path('passkey') required String? passkey,
    @Body() required AdvancedConfig? body,
    @chopper.Tag()
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
  });

  ///Login the user with email and password
  Future<chopper.Response<AuthResponse>> authLoginPost({
    required AuthLoginPost$RequestBody? body,
  }) {
    generatedMapping.putIfAbsent(
      AuthResponse,
      () => AuthResponse.fromJsonFactory,
    );

    return _authLoginPost(body: body);
  }

  ///Login the user with email and password
  @POST(path: '/auth/login', optionalBody: true)
  Future<chopper.Response<AuthResponse>> _authLoginPost({
    @Body() required AuthLoginPost$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Logout from a session, given the latest refresh token
  Future<chopper.Response> authLogoutPost({
    required AuthLogoutPost$RequestBody? body,
  }) {
    return _authLogoutPost(body: body);
  }

  ///Logout from a session, given the latest refresh token
  @POST(path: '/auth/logout', optionalBody: true)
  Future<chopper.Response> _authLogoutPost({
    @Body() required AuthLogoutPost$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Retrieve a new access token using the refresh token
  Future<chopper.Response<AuthResponse>> authRefreshPost({
    required AuthRefreshPost$RequestBody? body,
  }) {
    generatedMapping.putIfAbsent(
      AuthResponse,
      () => AuthResponse.fromJsonFactory,
    );

    return _authRefreshPost(body: body);
  }

  ///Retrieve a new access token using the refresh token
  @POST(path: '/auth/refresh', optionalBody: true)
  Future<chopper.Response<AuthResponse>> _authRefreshPost({
    @Body() required AuthRefreshPost$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Return the diagnostic
  Future<chopper.Response<String>> diagGet() {
    return _diagGet();
  }

  ///Return the diagnostic
  @GET(path: '/diag')
  Future<chopper.Response<String>> _diagGet({
    @chopper.Tag()
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
  });

  ///Hello World
  Future<chopper.Response<Hello>> helloGet() {
    generatedMapping.putIfAbsent(Hello, () => Hello.fromJsonFactory);

    return _helloGet();
  }

  ///Hello World
  @GET(path: '/hello')
  Future<chopper.Response<Hello>> _helloGet({
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Hello World',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["System"],
      deprecated: false,
    ),
  });

  ///Allows listing network interfaces
  Future<chopper.Response<List<NetworkInterface>>> networkInterfacesGet() {
    generatedMapping.putIfAbsent(
      NetworkInterface,
      () => NetworkInterface.fromJsonFactory,
    );

    return _networkInterfacesGet();
  }

  ///Allows listing network interfaces
  @GET(path: '/network/interfaces')
  Future<chopper.Response<List<NetworkInterface>>> _networkInterfacesGet({
    @chopper.Tag()
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
  });

  ///Allows configuring a network interface
  Future<chopper.Response> networkInterfacesInterfacePut({
    required String? interface,
    required InterfaceConfig? body,
  }) {
    return _networkInterfacesInterfacePut(interface: interface, body: body);
  }

  ///Allows configuring a network interface
  @PUT(path: '/network/interfaces/{interface}', optionalBody: true)
  Future<chopper.Response> _networkInterfacesInterfacePut({
    @Path('interface') required String? interface,
    @Body() required InterfaceConfig? body,
    @chopper.Tag()
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
  });

  ///To power off or reboot the device
  Future<chopper.Response> powerPost({required PowerPost$RequestBody? body}) {
    return _powerPost(body: body);
  }

  ///To power off or reboot the device
  @POST(path: '/power', optionalBody: true)
  Future<chopper.Response> _powerPost({
    @Body() required PowerPost$RequestBody? body,
    @chopper.Tag()
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
  });

  ///To reset the device
  Future<chopper.Response> resetPost({required ResetPost$RequestBody? body}) {
    return _resetPost(body: body);
  }

  ///To reset the device
  @POST(path: '/reset', optionalBody: true)
  Future<chopper.Response> _resetPost({
    @Body() required ResetPost$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Get the SMTP relay current configuration
  Future<chopper.Response<SMTPConfig>> smtpGet() {
    generatedMapping.putIfAbsent(SMTPConfig, () => SMTPConfig.fromJsonFactory);

    return _smtpGet();
  }

  ///Get the SMTP relay current configuration
  @GET(path: '/smtp')
  Future<chopper.Response<SMTPConfig>> _smtpGet({
    @chopper.Tag()
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
  });

  ///Set the current SMTP relay configuration
  Future<chopper.Response> smtpPost({required SMTPConfig? body}) {
    return _smtpPost(body: body);
  }

  ///Set the current SMTP relay configuration
  @POST(path: '/smtp', optionalBody: true)
  Future<chopper.Response> _smtpPost({
    @Body() required SMTPConfig? body,
    @chopper.Tag()
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
  });

  ///Get the device's status
  Future<chopper.Response<Status>> statusGet() {
    generatedMapping.putIfAbsent(Status, () => Status.fromJsonFactory);

    return _statusGet();
  }

  ///Get the device's status
  @GET(path: '/status')
  Future<chopper.Response<Status>> _statusGet({
    @chopper.Tag()
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
  });

  ///Get the OOBE status
  Future<chopper.Response<Oobe>> statusOobeGet() {
    generatedMapping.putIfAbsent(Oobe, () => Oobe.fromJsonFactory);

    return _statusOobeGet();
  }

  ///Get the OOBE status
  @GET(path: '/status/oobe')
  Future<chopper.Response<Oobe>> _statusOobeGet({
    @chopper.Tag()
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
  });

  ///Returns the system's current time configuration
  Future<chopper.Response<TimeConfig>> timeGet() {
    generatedMapping.putIfAbsent(TimeConfig, () => TimeConfig.fromJsonFactory);

    return _timeGet();
  }

  ///Returns the system's current time configuration
  @GET(path: '/time')
  Future<chopper.Response<TimeConfig>> _timeGet({
    @chopper.Tag()
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
  });

  ///
  Future<chopper.Response> timePost({required TimeConfig? body}) {
    return _timePost(body: body);
  }

  ///
  @POST(path: '/time', optionalBody: true)
  Future<chopper.Response> _timePost({
    @Body() required TimeConfig? body,
    @chopper.Tag()
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
  });

  ///Return available updates
  ///@param type Type of update we want to allow
  ///@param force Force the check of the available versions
  Future<chopper.Response<List<Update>>> updateGet({
    enums.UpdateType? type,
    bool? force,
  }) {
    generatedMapping.putIfAbsent(Update, () => Update.fromJsonFactory);

    return _updateGet(type: type?.value?.toString(), force: force);
  }

  ///Return available updates
  ///@param type Type of update we want to allow
  ///@param force Force the check of the available versions
  @GET(path: '/update')
  Future<chopper.Response<List<Update>>> _updateGet({
    @Query('type') String? type,
    @Query('force') bool? force,
    @chopper.Tag()
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
  });

  ///Apply update
  Future<chopper.Response<UpdateInfo>> updatePost({required Update? body}) {
    generatedMapping.putIfAbsent(UpdateInfo, () => UpdateInfo.fromJsonFactory);

    return _updatePost(body: body);
  }

  ///Apply update
  @POST(path: '/update', optionalBody: true)
  Future<chopper.Response<UpdateInfo>> _updatePost({
    @Body() required Update? body,
    @chopper.Tag()
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
  });

  ///Return the progress of the current update
  Future<chopper.Response<UpdateProgress>> updateProgressGet() {
    generatedMapping.putIfAbsent(
      UpdateProgress,
      () => UpdateProgress.fromJsonFactory,
    );

    return _updateProgressGet();
  }

  ///Return the progress of the current update
  @GET(path: '/update/progress')
  Future<chopper.Response<UpdateProgress>> _updateProgressGet({
    @chopper.Tag()
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
  });

  ///Start an update using the uploaded file
  Future<chopper.Response<UpdateInfo>> updateUploadPost({
    required Object? body,
  }) {
    generatedMapping.putIfAbsent(UpdateInfo, () => UpdateInfo.fromJsonFactory);

    return _updateUploadPost(body: body);
  }

  ///Start an update using the uploaded file
  @POST(path: '/update/upload', optionalBody: true)
  Future<chopper.Response<UpdateInfo>> _updateUploadPost({
    @Body() required Object? body,
    @chopper.Tag()
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
  });

  ///List users
  Future<chopper.Response<List<User>>> usersGet() {
    generatedMapping.putIfAbsent(User, () => User.fromJsonFactory);

    return _usersGet();
  }

  ///List users
  @GET(path: '/users')
  Future<chopper.Response<List<User>>> _usersGet({
    @chopper.Tag()
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
  });

  ///Delete the user
  Future<chopper.Response> usersIdDelete({required String? id}) {
    return _usersIdDelete(id: id);
  }

  ///Delete the user
  @DELETE(path: '/users/{id}')
  Future<chopper.Response> _usersIdDelete({
    @Path('id') required String? id,
    @chopper.Tag()
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
  });

  ///Get the user's information
  Future<chopper.Response<User>> usersIdGet({required String? id}) {
    generatedMapping.putIfAbsent(User, () => User.fromJsonFactory);

    return _usersIdGet(id: id);
  }

  ///Get the user's information
  @GET(path: '/users/{id}')
  Future<chopper.Response<User>> _usersIdGet({
    @Path('id') required String? id,
    @chopper.Tag()
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
  });

  ///Update the user's information
  Future<chopper.Response> usersIdPut({
    required String? id,
    required UsersIdPut$RequestBody? body,
  }) {
    return _usersIdPut(id: id, body: body);
  }

  ///Update the user's information
  @PUT(path: '/users/{id}', optionalBody: true)
  Future<chopper.Response> _usersIdPut({
    @Path('id') required String? id,
    @Body() required UsersIdPut$RequestBody? body,
    @chopper.Tag()
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
  });

  ///List pending user invites
  Future<chopper.Response<List<Invite>>> usersInvitesGet() {
    generatedMapping.putIfAbsent(Invite, () => Invite.fromJsonFactory);

    return _usersInvitesGet();
  }

  ///List pending user invites
  @GET(path: '/users/invites')
  Future<chopper.Response<List<Invite>>> _usersInvitesGet({
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'List pending user invites',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users, not finalized"],
      deprecated: false,
    ),
  });

  ///Create a new user invite
  Future<chopper.Response> usersInvitesPost({
    required UsersInvitesPost$RequestBody? body,
  }) {
    return _usersInvitesPost(body: body);
  }

  ///Create a new user invite
  @POST(path: '/users/invites', optionalBody: true)
  Future<chopper.Response> _usersInvitesPost({
    @Body() required UsersInvitesPost$RequestBody? body,
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Create a new user invite',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users, not finalized"],
      deprecated: false,
    ),
  });

  ///Remove the invite for the given email
  Future<chopper.Response> usersInvitesEmailDelete({required String? email}) {
    return _usersInvitesEmailDelete(email: email);
  }

  ///Remove the invite for the given email
  @DELETE(path: '/users/invites/{email}')
  Future<chopper.Response> _usersInvitesEmailDelete({
    @Path('email') required String? email,
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Remove the invite for the given email',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users, not finalized"],
      deprecated: false,
    ),
  });

  ///Confirm an invite and create the user
  Future<chopper.Response> usersInvitesEmailPut({
    required String? email,
    required UsersInvitesEmailPut$RequestBody? body,
  }) {
    return _usersInvitesEmailPut(email: email, body: body);
  }

  ///Confirm an invite and create the user
  @PUT(path: '/users/invites/{email}', optionalBody: true)
  Future<chopper.Response> _usersInvitesEmailPut({
    @Path('email') required String? email,
    @Body() required UsersInvitesEmailPut$RequestBody? body,
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Confirm an invite and create the user',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["users, not finalized"],
      deprecated: false,
    ),
  });

  ///Get my own user information
  Future<chopper.Response<User>> usersMeGet() {
    generatedMapping.putIfAbsent(User, () => User.fromJsonFactory);

    return _usersMeGet();
  }

  ///Get my own user information
  @GET(path: '/users/me')
  Future<chopper.Response<User>> _usersMeGet({
    @chopper.Tag()
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
  });

  ///Update my own user information
  Future<chopper.Response> usersMePut({required UsersMePut$RequestBody? body}) {
    return _usersMePut(body: body);
  }

  ///Update my own user information
  @PUT(path: '/users/me', optionalBody: true)
  Future<chopper.Response> _usersMePut({
    @Body() required UsersMePut$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Get the owner user information
  Future<chopper.Response<User>> usersOwnerGet() {
    generatedMapping.putIfAbsent(User, () => User.fromJsonFactory);

    return _usersOwnerGet();
  }

  ///Get the owner user information
  @GET(path: '/users/owner')
  Future<chopper.Response<User>> _usersOwnerGet({
    @chopper.Tag()
    SwaggerMetaData swaggerMetaData = const SwaggerMetaData(
      description: '',
      summary: 'Get the owner user information',
      operationId: '',
      consumes: [],
      produces: [],
      security: [],
      tags: ["OOBE"],
      deprecated: false,
    ),
  });

  ///Create the owner user
  Future<chopper.Response> usersOwnerPost({
    required UsersOwnerPost$RequestBody? body,
  }) {
    return _usersOwnerPost(body: body);
  }

  ///Create the owner user
  @POST(path: '/users/owner', optionalBody: true)
  Future<chopper.Response> _usersOwnerPost({
    @Body() required UsersOwnerPost$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Confirm and create the owner user
  Future<chopper.Response> usersOwnerPut({
    required UsersOwnerPut$RequestBody? body,
  }) {
    return _usersOwnerPut(body: body);
  }

  ///Confirm and create the owner user
  @PUT(path: '/users/owner', optionalBody: true)
  Future<chopper.Response> _usersOwnerPut({
    @Body() required UsersOwnerPut$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Get the current Wi-Fi configuration
  Future<chopper.Response<WifiConfig>> wifiGet() {
    generatedMapping.putIfAbsent(WifiConfig, () => WifiConfig.fromJsonFactory);

    return _wifiGet();
  }

  ///Get the current Wi-Fi configuration
  @GET(path: '/wifi')
  Future<chopper.Response<WifiConfig>> _wifiGet({
    @chopper.Tag()
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
  });

  ///Set the current Wi-Fi configuration
  Future<chopper.Response<WifiConfig>> wifiPost({required WifiConfig? body}) {
    generatedMapping.putIfAbsent(WifiConfig, () => WifiConfig.fromJsonFactory);

    return _wifiPost(body: body);
  }

  ///Set the current Wi-Fi configuration
  @POST(path: '/wifi', optionalBody: true)
  Future<chopper.Response<WifiConfig>> _wifiPost({
    @Body() required WifiConfig? body,
    @chopper.Tag()
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
  });

  ///Set the current Wi-Fi configuration
  Future<chopper.Response<List<WifiConfig>>> wifiScanPost() {
    generatedMapping.putIfAbsent(WifiConfig, () => WifiConfig.fromJsonFactory);

    return _wifiScanPost();
  }

  ///Set the current Wi-Fi configuration
  @POST(path: '/wifi/scan', optionalBody: true)
  Future<chopper.Response<List<WifiConfig>>> _wifiScanPost({
    @chopper.Tag()
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
  });
}

@JsonSerializable(explicitToJson: true)
class About {
  const About({
    required this.certificateCommonName,
    required this.date,
    required this.defaultMacAddr,
    required this.hardwareInfo,
    required this.hostname,
    required this.installId,
    required this.modelName,
    required this.modelNumber,
    required this.networkInterfaces,
    required this.osState,
    required this.productId,
    required this.serialNumber,
    required this.version,
  });

  factory About.fromJson(Map<String, dynamic> json) => _$AboutFromJson(json);

  static const toJsonFactory = _$AboutToJson;
  Map<String, dynamic> toJson() => _$AboutToJson(this);

  @JsonKey(name: 'certificate_common_name')
  final String certificateCommonName;
  @JsonKey(name: 'date')
  final DateTime date;
  @JsonKey(name: 'default_mac_addr')
  final String defaultMacAddr;
  @JsonKey(name: 'hardware_info')
  final AboutHardware hardwareInfo;
  @JsonKey(name: 'hostname')
  final String hostname;
  @JsonKey(name: 'install_id')
  final String installId;
  @JsonKey(name: 'model_name')
  final String modelName;
  @JsonKey(name: 'model_number')
  final String modelNumber;
  @JsonKey(name: 'network_interfaces', defaultValue: <AboutNetwork>[])
  final List<AboutNetwork> networkInterfaces;
  @JsonKey(
    name: 'os_state',
    toJson: aboutOsStateToJson,
    fromJson: aboutOsStateFromJson,
  )
  final enums.AboutOsState osState;
  @JsonKey(name: 'product_id')
  final String productId;
  @JsonKey(name: 'serial_number')
  final String serialNumber;
  @JsonKey(name: 'version')
  final String version;
  static const fromJsonFactory = _$AboutFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is About &&
            (identical(other.certificateCommonName, certificateCommonName) ||
                const DeepCollectionEquality().equals(
                  other.certificateCommonName,
                  certificateCommonName,
                )) &&
            (identical(other.date, date) ||
                const DeepCollectionEquality().equals(other.date, date)) &&
            (identical(other.defaultMacAddr, defaultMacAddr) ||
                const DeepCollectionEquality().equals(
                  other.defaultMacAddr,
                  defaultMacAddr,
                )) &&
            (identical(other.hardwareInfo, hardwareInfo) ||
                const DeepCollectionEquality().equals(
                  other.hardwareInfo,
                  hardwareInfo,
                )) &&
            (identical(other.hostname, hostname) ||
                const DeepCollectionEquality().equals(
                  other.hostname,
                  hostname,
                )) &&
            (identical(other.installId, installId) ||
                const DeepCollectionEquality().equals(
                  other.installId,
                  installId,
                )) &&
            (identical(other.modelName, modelName) ||
                const DeepCollectionEquality().equals(
                  other.modelName,
                  modelName,
                )) &&
            (identical(other.modelNumber, modelNumber) ||
                const DeepCollectionEquality().equals(
                  other.modelNumber,
                  modelNumber,
                )) &&
            (identical(other.networkInterfaces, networkInterfaces) ||
                const DeepCollectionEquality().equals(
                  other.networkInterfaces,
                  networkInterfaces,
                )) &&
            (identical(other.osState, osState) ||
                const DeepCollectionEquality().equals(
                  other.osState,
                  osState,
                )) &&
            (identical(other.productId, productId) ||
                const DeepCollectionEquality().equals(
                  other.productId,
                  productId,
                )) &&
            (identical(other.serialNumber, serialNumber) ||
                const DeepCollectionEquality().equals(
                  other.serialNumber,
                  serialNumber,
                )) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(other.version, version)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(certificateCommonName) ^
      const DeepCollectionEquality().hash(date) ^
      const DeepCollectionEquality().hash(defaultMacAddr) ^
      const DeepCollectionEquality().hash(hardwareInfo) ^
      const DeepCollectionEquality().hash(hostname) ^
      const DeepCollectionEquality().hash(installId) ^
      const DeepCollectionEquality().hash(modelName) ^
      const DeepCollectionEquality().hash(modelNumber) ^
      const DeepCollectionEquality().hash(networkInterfaces) ^
      const DeepCollectionEquality().hash(osState) ^
      const DeepCollectionEquality().hash(productId) ^
      const DeepCollectionEquality().hash(serialNumber) ^
      const DeepCollectionEquality().hash(version) ^
      runtimeType.hashCode;
}

extension $AboutExtension on About {
  About copyWith({
    String? certificateCommonName,
    DateTime? date,
    String? defaultMacAddr,
    AboutHardware? hardwareInfo,
    String? hostname,
    String? installId,
    String? modelName,
    String? modelNumber,
    List<AboutNetwork>? networkInterfaces,
    enums.AboutOsState? osState,
    String? productId,
    String? serialNumber,
    String? version,
  }) {
    return About(
      certificateCommonName:
          certificateCommonName ?? this.certificateCommonName,
      date: date ?? this.date,
      defaultMacAddr: defaultMacAddr ?? this.defaultMacAddr,
      hardwareInfo: hardwareInfo ?? this.hardwareInfo,
      hostname: hostname ?? this.hostname,
      installId: installId ?? this.installId,
      modelName: modelName ?? this.modelName,
      modelNumber: modelNumber ?? this.modelNumber,
      networkInterfaces: networkInterfaces ?? this.networkInterfaces,
      osState: osState ?? this.osState,
      productId: productId ?? this.productId,
      serialNumber: serialNumber ?? this.serialNumber,
      version: version ?? this.version,
    );
  }

  About copyWithWrapped({
    Wrapped<String>? certificateCommonName,
    Wrapped<DateTime>? date,
    Wrapped<String>? defaultMacAddr,
    Wrapped<AboutHardware>? hardwareInfo,
    Wrapped<String>? hostname,
    Wrapped<String>? installId,
    Wrapped<String>? modelName,
    Wrapped<String>? modelNumber,
    Wrapped<List<AboutNetwork>>? networkInterfaces,
    Wrapped<enums.AboutOsState>? osState,
    Wrapped<String>? productId,
    Wrapped<String>? serialNumber,
    Wrapped<String>? version,
  }) {
    return About(
      certificateCommonName: (certificateCommonName != null
          ? certificateCommonName.value
          : this.certificateCommonName),
      date: (date != null ? date.value : this.date),
      defaultMacAddr: (defaultMacAddr != null
          ? defaultMacAddr.value
          : this.defaultMacAddr),
      hardwareInfo: (hardwareInfo != null
          ? hardwareInfo.value
          : this.hardwareInfo),
      hostname: (hostname != null ? hostname.value : this.hostname),
      installId: (installId != null ? installId.value : this.installId),
      modelName: (modelName != null ? modelName.value : this.modelName),
      modelNumber: (modelNumber != null ? modelNumber.value : this.modelNumber),
      networkInterfaces: (networkInterfaces != null
          ? networkInterfaces.value
          : this.networkInterfaces),
      osState: (osState != null ? osState.value : this.osState),
      productId: (productId != null ? productId.value : this.productId),
      serialNumber: (serialNumber != null
          ? serialNumber.value
          : this.serialNumber),
      version: (version != null ? version.value : this.version),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AboutHardware {
  const AboutHardware({
    required this.memory,
    required this.processorCount,
    required this.processorType,
  });

  factory AboutHardware.fromJson(Map<String, dynamic> json) =>
      _$AboutHardwareFromJson(json);

  static const toJsonFactory = _$AboutHardwareToJson;
  Map<String, dynamic> toJson() => _$AboutHardwareToJson(this);

  @JsonKey(name: 'memory')
  final double memory;
  @JsonKey(name: 'processor_count')
  final int processorCount;
  @JsonKey(name: 'processor_type')
  final String processorType;
  static const fromJsonFactory = _$AboutHardwareFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AboutHardware &&
            (identical(other.memory, memory) ||
                const DeepCollectionEquality().equals(other.memory, memory)) &&
            (identical(other.processorCount, processorCount) ||
                const DeepCollectionEquality().equals(
                  other.processorCount,
                  processorCount,
                )) &&
            (identical(other.processorType, processorType) ||
                const DeepCollectionEquality().equals(
                  other.processorType,
                  processorType,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(memory) ^
      const DeepCollectionEquality().hash(processorCount) ^
      const DeepCollectionEquality().hash(processorType) ^
      runtimeType.hashCode;
}

extension $AboutHardwareExtension on AboutHardware {
  AboutHardware copyWith({
    double? memory,
    int? processorCount,
    String? processorType,
  }) {
    return AboutHardware(
      memory: memory ?? this.memory,
      processorCount: processorCount ?? this.processorCount,
      processorType: processorType ?? this.processorType,
    );
  }

  AboutHardware copyWithWrapped({
    Wrapped<double>? memory,
    Wrapped<int>? processorCount,
    Wrapped<String>? processorType,
  }) {
    return AboutHardware(
      memory: (memory != null ? memory.value : this.memory),
      processorCount: (processorCount != null
          ? processorCount.value
          : this.processorCount),
      processorType: (processorType != null
          ? processorType.value
          : this.processorType),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AboutIPv4Info {
  const AboutIPv4Info({
    required this.gateway,
    required this.ipv4,
    required this.netmask,
  });

  factory AboutIPv4Info.fromJson(Map<String, dynamic> json) =>
      _$AboutIPv4InfoFromJson(json);

  static const toJsonFactory = _$AboutIPv4InfoToJson;
  Map<String, dynamic> toJson() => _$AboutIPv4InfoToJson(this);

  @JsonKey(name: 'gateway')
  final String gateway;
  @JsonKey(name: 'ipv4')
  final String ipv4;
  @JsonKey(name: 'netmask')
  final String netmask;
  static const fromJsonFactory = _$AboutIPv4InfoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AboutIPv4Info &&
            (identical(other.gateway, gateway) ||
                const DeepCollectionEquality().equals(
                  other.gateway,
                  gateway,
                )) &&
            (identical(other.ipv4, ipv4) ||
                const DeepCollectionEquality().equals(other.ipv4, ipv4)) &&
            (identical(other.netmask, netmask) ||
                const DeepCollectionEquality().equals(other.netmask, netmask)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(gateway) ^
      const DeepCollectionEquality().hash(ipv4) ^
      const DeepCollectionEquality().hash(netmask) ^
      runtimeType.hashCode;
}

extension $AboutIPv4InfoExtension on AboutIPv4Info {
  AboutIPv4Info copyWith({String? gateway, String? ipv4, String? netmask}) {
    return AboutIPv4Info(
      gateway: gateway ?? this.gateway,
      ipv4: ipv4 ?? this.ipv4,
      netmask: netmask ?? this.netmask,
    );
  }

  AboutIPv4Info copyWithWrapped({
    Wrapped<String>? gateway,
    Wrapped<String>? ipv4,
    Wrapped<String>? netmask,
  }) {
    return AboutIPv4Info(
      gateway: (gateway != null ? gateway.value : this.gateway),
      ipv4: (ipv4 != null ? ipv4.value : this.ipv4),
      netmask: (netmask != null ? netmask.value : this.netmask),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AboutNetwork {
  const AboutNetwork({
    this.ipv4Info,
    this.link,
    required this.macAddress,
    required this.name,
    required this.type,
  });

  factory AboutNetwork.fromJson(Map<String, dynamic> json) =>
      _$AboutNetworkFromJson(json);

  static const toJsonFactory = _$AboutNetworkToJson;
  Map<String, dynamic> toJson() => _$AboutNetworkToJson(this);

  @JsonKey(name: 'ipv4_info')
  final AboutIPv4Info? ipv4Info;
  @JsonKey(name: 'link')
  final String? link;
  @JsonKey(name: 'mac_address')
  final String macAddress;
  @JsonKey(name: 'name')
  final String name;
  @JsonKey(
    name: 'type',
    toJson: aboutNetworkTypeToJson,
    fromJson: aboutNetworkTypeFromJson,
  )
  final enums.AboutNetworkType type;
  static const fromJsonFactory = _$AboutNetworkFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AboutNetwork &&
            (identical(other.ipv4Info, ipv4Info) ||
                const DeepCollectionEquality().equals(
                  other.ipv4Info,
                  ipv4Info,
                )) &&
            (identical(other.link, link) ||
                const DeepCollectionEquality().equals(other.link, link)) &&
            (identical(other.macAddress, macAddress) ||
                const DeepCollectionEquality().equals(
                  other.macAddress,
                  macAddress,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(ipv4Info) ^
      const DeepCollectionEquality().hash(link) ^
      const DeepCollectionEquality().hash(macAddress) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(type) ^
      runtimeType.hashCode;
}

extension $AboutNetworkExtension on AboutNetwork {
  AboutNetwork copyWith({
    AboutIPv4Info? ipv4Info,
    String? link,
    String? macAddress,
    String? name,
    enums.AboutNetworkType? type,
  }) {
    return AboutNetwork(
      ipv4Info: ipv4Info ?? this.ipv4Info,
      link: link ?? this.link,
      macAddress: macAddress ?? this.macAddress,
      name: name ?? this.name,
      type: type ?? this.type,
    );
  }

  AboutNetwork copyWithWrapped({
    Wrapped<AboutIPv4Info?>? ipv4Info,
    Wrapped<String?>? link,
    Wrapped<String>? macAddress,
    Wrapped<String>? name,
    Wrapped<enums.AboutNetworkType>? type,
  }) {
    return AboutNetwork(
      ipv4Info: (ipv4Info != null ? ipv4Info.value : this.ipv4Info),
      link: (link != null ? link.value : this.link),
      macAddress: (macAddress != null ? macAddress.value : this.macAddress),
      name: (name != null ? name.value : this.name),
      type: (type != null ? type.value : this.type),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AdvancedConfig {
  const AdvancedConfig({
    required this.sshEnabled,
    required this.swaggerUiEnabled,
    required this.updateLabels,
  });

  factory AdvancedConfig.fromJson(Map<String, dynamic> json) =>
      _$AdvancedConfigFromJson(json);

  static const toJsonFactory = _$AdvancedConfigToJson;
  Map<String, dynamic> toJson() => _$AdvancedConfigToJson(this);

  @JsonKey(name: 'ssh_enabled')
  final bool sshEnabled;
  @JsonKey(name: 'swagger_ui_enabled')
  final bool swaggerUiEnabled;
  @JsonKey(name: 'update_labels', defaultValue: <UpdateLabel>[])
  final List<UpdateLabel> updateLabels;
  static const fromJsonFactory = _$AdvancedConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AdvancedConfig &&
            (identical(other.sshEnabled, sshEnabled) ||
                const DeepCollectionEquality().equals(
                  other.sshEnabled,
                  sshEnabled,
                )) &&
            (identical(other.swaggerUiEnabled, swaggerUiEnabled) ||
                const DeepCollectionEquality().equals(
                  other.swaggerUiEnabled,
                  swaggerUiEnabled,
                )) &&
            (identical(other.updateLabels, updateLabels) ||
                const DeepCollectionEquality().equals(
                  other.updateLabels,
                  updateLabels,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(sshEnabled) ^
      const DeepCollectionEquality().hash(swaggerUiEnabled) ^
      const DeepCollectionEquality().hash(updateLabels) ^
      runtimeType.hashCode;
}

extension $AdvancedConfigExtension on AdvancedConfig {
  AdvancedConfig copyWith({
    bool? sshEnabled,
    bool? swaggerUiEnabled,
    List<UpdateLabel>? updateLabels,
  }) {
    return AdvancedConfig(
      sshEnabled: sshEnabled ?? this.sshEnabled,
      swaggerUiEnabled: swaggerUiEnabled ?? this.swaggerUiEnabled,
      updateLabels: updateLabels ?? this.updateLabels,
    );
  }

  AdvancedConfig copyWithWrapped({
    Wrapped<bool>? sshEnabled,
    Wrapped<bool>? swaggerUiEnabled,
    Wrapped<List<UpdateLabel>>? updateLabels,
  }) {
    return AdvancedConfig(
      sshEnabled: (sshEnabled != null ? sshEnabled.value : this.sshEnabled),
      swaggerUiEnabled: (swaggerUiEnabled != null
          ? swaggerUiEnabled.value
          : this.swaggerUiEnabled),
      updateLabels: (updateLabels != null
          ? updateLabels.value
          : this.updateLabels),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AppStatus {
  const AppStatus({required this.files, required this.photos});

  factory AppStatus.fromJson(Map<String, dynamic> json) =>
      _$AppStatusFromJson(json);

  static const toJsonFactory = _$AppStatusToJson;
  Map<String, dynamic> toJson() => _$AppStatusToJson(this);

  @JsonKey(name: 'files')
  final String files;
  @JsonKey(name: 'photos')
  final String photos;
  static const fromJsonFactory = _$AppStatusFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AppStatus &&
            (identical(other.files, files) ||
                const DeepCollectionEquality().equals(other.files, files)) &&
            (identical(other.photos, photos) ||
                const DeepCollectionEquality().equals(other.photos, photos)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(files) ^
      const DeepCollectionEquality().hash(photos) ^
      runtimeType.hashCode;
}

extension $AppStatusExtension on AppStatus {
  AppStatus copyWith({String? files, String? photos}) {
    return AppStatus(files: files ?? this.files, photos: photos ?? this.photos);
  }

  AppStatus copyWithWrapped({Wrapped<String>? files, Wrapped<String>? photos}) {
    return AppStatus(
      files: (files != null ? files.value : this.files),
      photos: (photos != null ? photos.value : this.photos),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AuthResponse {
  const AuthResponse({
    required this.accessToken,
    required this.expiresIn,
    required this.refreshToken,
    required this.type,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) =>
      _$AuthResponseFromJson(json);

  static const toJsonFactory = _$AuthResponseToJson;
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);

  @JsonKey(name: 'access_token')
  final String accessToken;
  @JsonKey(name: 'expires_in')
  final int expiresIn;
  @JsonKey(name: 'refresh_token')
  final String refreshToken;
  @JsonKey(
    name: 'type',
    toJson: authResponseTypeToJson,
    fromJson: authResponseTypeFromJson,
  )
  final enums.AuthResponseType type;
  static const fromJsonFactory = _$AuthResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AuthResponse &&
            (identical(other.accessToken, accessToken) ||
                const DeepCollectionEquality().equals(
                  other.accessToken,
                  accessToken,
                )) &&
            (identical(other.expiresIn, expiresIn) ||
                const DeepCollectionEquality().equals(
                  other.expiresIn,
                  expiresIn,
                )) &&
            (identical(other.refreshToken, refreshToken) ||
                const DeepCollectionEquality().equals(
                  other.refreshToken,
                  refreshToken,
                )) &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(accessToken) ^
      const DeepCollectionEquality().hash(expiresIn) ^
      const DeepCollectionEquality().hash(refreshToken) ^
      const DeepCollectionEquality().hash(type) ^
      runtimeType.hashCode;
}

extension $AuthResponseExtension on AuthResponse {
  AuthResponse copyWith({
    String? accessToken,
    int? expiresIn,
    String? refreshToken,
    enums.AuthResponseType? type,
  }) {
    return AuthResponse(
      accessToken: accessToken ?? this.accessToken,
      expiresIn: expiresIn ?? this.expiresIn,
      refreshToken: refreshToken ?? this.refreshToken,
      type: type ?? this.type,
    );
  }

  AuthResponse copyWithWrapped({
    Wrapped<String>? accessToken,
    Wrapped<int>? expiresIn,
    Wrapped<String>? refreshToken,
    Wrapped<enums.AuthResponseType>? type,
  }) {
    return AuthResponse(
      accessToken: (accessToken != null ? accessToken.value : this.accessToken),
      expiresIn: (expiresIn != null ? expiresIn.value : this.expiresIn),
      refreshToken: (refreshToken != null
          ? refreshToken.value
          : this.refreshToken),
      type: (type != null ? type.value : this.type),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DeviceConfiguration {
  const DeviceConfiguration({
    this.deviceCertificateSignedBy,
    required this.prodFailureReasons,
    required this.prodReady,
    required this.provisioningVault,
    required this.secureBootEnabled,
  });

  factory DeviceConfiguration.fromJson(Map<String, dynamic> json) =>
      _$DeviceConfigurationFromJson(json);

  static const toJsonFactory = _$DeviceConfigurationToJson;
  Map<String, dynamic> toJson() => _$DeviceConfigurationToJson(this);

  @JsonKey(name: 'device_certificate_signed_by')
  final DeviceConfigurationCertificate? deviceCertificateSignedBy;
  @JsonKey(name: 'prod_failure_reasons', defaultValue: <String>[])
  final List<String> prodFailureReasons;
  @JsonKey(name: 'prod_ready')
  final bool prodReady;
  @JsonKey(name: 'provisioning_vault')
  final DeviceConfigurationProvisioningVault provisioningVault;
  @JsonKey(name: 'secure_boot_enabled')
  final bool secureBootEnabled;
  static const fromJsonFactory = _$DeviceConfigurationFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DeviceConfiguration &&
            (identical(
                  other.deviceCertificateSignedBy,
                  deviceCertificateSignedBy,
                ) ||
                const DeepCollectionEquality().equals(
                  other.deviceCertificateSignedBy,
                  deviceCertificateSignedBy,
                )) &&
            (identical(other.prodFailureReasons, prodFailureReasons) ||
                const DeepCollectionEquality().equals(
                  other.prodFailureReasons,
                  prodFailureReasons,
                )) &&
            (identical(other.prodReady, prodReady) ||
                const DeepCollectionEquality().equals(
                  other.prodReady,
                  prodReady,
                )) &&
            (identical(other.provisioningVault, provisioningVault) ||
                const DeepCollectionEquality().equals(
                  other.provisioningVault,
                  provisioningVault,
                )) &&
            (identical(other.secureBootEnabled, secureBootEnabled) ||
                const DeepCollectionEquality().equals(
                  other.secureBootEnabled,
                  secureBootEnabled,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(deviceCertificateSignedBy) ^
      const DeepCollectionEquality().hash(prodFailureReasons) ^
      const DeepCollectionEquality().hash(prodReady) ^
      const DeepCollectionEquality().hash(provisioningVault) ^
      const DeepCollectionEquality().hash(secureBootEnabled) ^
      runtimeType.hashCode;
}

extension $DeviceConfigurationExtension on DeviceConfiguration {
  DeviceConfiguration copyWith({
    DeviceConfigurationCertificate? deviceCertificateSignedBy,
    List<String>? prodFailureReasons,
    bool? prodReady,
    DeviceConfigurationProvisioningVault? provisioningVault,
    bool? secureBootEnabled,
  }) {
    return DeviceConfiguration(
      deviceCertificateSignedBy:
          deviceCertificateSignedBy ?? this.deviceCertificateSignedBy,
      prodFailureReasons: prodFailureReasons ?? this.prodFailureReasons,
      prodReady: prodReady ?? this.prodReady,
      provisioningVault: provisioningVault ?? this.provisioningVault,
      secureBootEnabled: secureBootEnabled ?? this.secureBootEnabled,
    );
  }

  DeviceConfiguration copyWithWrapped({
    Wrapped<DeviceConfigurationCertificate?>? deviceCertificateSignedBy,
    Wrapped<List<String>>? prodFailureReasons,
    Wrapped<bool>? prodReady,
    Wrapped<DeviceConfigurationProvisioningVault>? provisioningVault,
    Wrapped<bool>? secureBootEnabled,
  }) {
    return DeviceConfiguration(
      deviceCertificateSignedBy: (deviceCertificateSignedBy != null
          ? deviceCertificateSignedBy.value
          : this.deviceCertificateSignedBy),
      prodFailureReasons: (prodFailureReasons != null
          ? prodFailureReasons.value
          : this.prodFailureReasons),
      prodReady: (prodReady != null ? prodReady.value : this.prodReady),
      provisioningVault: (provisioningVault != null
          ? provisioningVault.value
          : this.provisioningVault),
      secureBootEnabled: (secureBootEnabled != null
          ? secureBootEnabled.value
          : this.secureBootEnabled),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DeviceConfigurationCertificate {
  const DeviceConfigurationCertificate({
    required this.name,
    required this.$value,
  });

  factory DeviceConfigurationCertificate.fromJson(Map<String, dynamic> json) =>
      _$DeviceConfigurationCertificateFromJson(json);

  static const toJsonFactory = _$DeviceConfigurationCertificateToJson;
  Map<String, dynamic> toJson() => _$DeviceConfigurationCertificateToJson(this);

  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'value')
  final String $value;
  static const fromJsonFactory = _$DeviceConfigurationCertificateFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DeviceConfigurationCertificate &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.$value, $value) ||
                const DeepCollectionEquality().equals(other.$value, $value)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash($value) ^
      runtimeType.hashCode;
}

extension $DeviceConfigurationCertificateExtension
    on DeviceConfigurationCertificate {
  DeviceConfigurationCertificate copyWith({String? name, String? $value}) {
    return DeviceConfigurationCertificate(
      name: name ?? this.name,
      $value: $value ?? this.$value,
    );
  }

  DeviceConfigurationCertificate copyWithWrapped({
    Wrapped<String>? name,
    Wrapped<String>? $value,
  }) {
    return DeviceConfigurationCertificate(
      name: (name != null ? name.value : this.name),
      $value: ($value != null ? $value.value : this.$value),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DeviceConfigurationProvisioningVault {
  const DeviceConfigurationProvisioningVault({
    this.ssid,
    required this.certificates,
    required this.creationDate,
    required this.signedBy,
  });

  factory DeviceConfigurationProvisioningVault.fromJson(
    Map<String, dynamic> json,
  ) => _$DeviceConfigurationProvisioningVaultFromJson(json);

  static const toJsonFactory = _$DeviceConfigurationProvisioningVaultToJson;
  Map<String, dynamic> toJson() =>
      _$DeviceConfigurationProvisioningVaultToJson(this);

  @JsonKey(name: 'SSID')
  final String? ssid;
  @JsonKey(
    name: 'certificates',
    defaultValue: <DeviceConfigurationCertificate>[],
  )
  final List<DeviceConfigurationCertificate> certificates;
  @JsonKey(name: 'creation_date')
  final DateTime creationDate;
  @JsonKey(name: 'signed_by')
  final DeviceConfigurationCertificate signedBy;
  static const fromJsonFactory = _$DeviceConfigurationProvisioningVaultFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DeviceConfigurationProvisioningVault &&
            (identical(other.ssid, ssid) ||
                const DeepCollectionEquality().equals(other.ssid, ssid)) &&
            (identical(other.certificates, certificates) ||
                const DeepCollectionEquality().equals(
                  other.certificates,
                  certificates,
                )) &&
            (identical(other.creationDate, creationDate) ||
                const DeepCollectionEquality().equals(
                  other.creationDate,
                  creationDate,
                )) &&
            (identical(other.signedBy, signedBy) ||
                const DeepCollectionEquality().equals(
                  other.signedBy,
                  signedBy,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(ssid) ^
      const DeepCollectionEquality().hash(certificates) ^
      const DeepCollectionEquality().hash(creationDate) ^
      const DeepCollectionEquality().hash(signedBy) ^
      runtimeType.hashCode;
}

extension $DeviceConfigurationProvisioningVaultExtension
    on DeviceConfigurationProvisioningVault {
  DeviceConfigurationProvisioningVault copyWith({
    String? ssid,
    List<DeviceConfigurationCertificate>? certificates,
    DateTime? creationDate,
    DeviceConfigurationCertificate? signedBy,
  }) {
    return DeviceConfigurationProvisioningVault(
      ssid: ssid ?? this.ssid,
      certificates: certificates ?? this.certificates,
      creationDate: creationDate ?? this.creationDate,
      signedBy: signedBy ?? this.signedBy,
    );
  }

  DeviceConfigurationProvisioningVault copyWithWrapped({
    Wrapped<String?>? ssid,
    Wrapped<List<DeviceConfigurationCertificate>>? certificates,
    Wrapped<DateTime>? creationDate,
    Wrapped<DeviceConfigurationCertificate>? signedBy,
  }) {
    return DeviceConfigurationProvisioningVault(
      ssid: (ssid != null ? ssid.value : this.ssid),
      certificates: (certificates != null
          ? certificates.value
          : this.certificates),
      creationDate: (creationDate != null
          ? creationDate.value
          : this.creationDate),
      signedBy: (signedBy != null ? signedBy.value : this.signedBy),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Error {
  const Error({required this.error, required this.message});

  factory Error.fromJson(Map<String, dynamic> json) => _$ErrorFromJson(json);

  static const toJsonFactory = _$ErrorToJson;
  Map<String, dynamic> toJson() => _$ErrorToJson(this);

  @JsonKey(name: 'error')
  final String error;
  @JsonKey(name: 'message')
  final String message;
  static const fromJsonFactory = _$ErrorFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Error &&
            (identical(other.error, error) ||
                const DeepCollectionEquality().equals(other.error, error)) &&
            (identical(other.message, message) ||
                const DeepCollectionEquality().equals(other.message, message)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(error) ^
      const DeepCollectionEquality().hash(message) ^
      runtimeType.hashCode;
}

extension $ErrorExtension on Error {
  Error copyWith({String? error, String? message}) {
    return Error(error: error ?? this.error, message: message ?? this.message);
  }

  Error copyWithWrapped({Wrapped<String>? error, Wrapped<String>? message}) {
    return Error(
      error: (error != null ? error.value : this.error),
      message: (message != null ? message.value : this.message),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class HardwareInfo {
  const HardwareInfo({
    required this.autoNegotiation,
    required this.isActive,
    required this.isLoopback,
    required this.macAddress,
    required this.maxSpeed,
    required this.maxSpeedDuplex,
    required this.maximumMtu,
    required this.minimumMtu,
    required this.model,
    required this.mtu,
    required this.vendor,
  });

  factory HardwareInfo.fromJson(Map<String, dynamic> json) =>
      _$HardwareInfoFromJson(json);

  static const toJsonFactory = _$HardwareInfoToJson;
  Map<String, dynamic> toJson() => _$HardwareInfoToJson(this);

  @JsonKey(name: 'auto_negotiation')
  final bool autoNegotiation;
  @JsonKey(name: 'is_active')
  final bool isActive;
  @JsonKey(name: 'is_loopback')
  final bool isLoopback;
  @JsonKey(name: 'mac_address')
  final String macAddress;
  @JsonKey(name: 'max_speed')
  final int maxSpeed;
  @JsonKey(
    name: 'max_speed_duplex',
    toJson: duplexTypeToJson,
    fromJson: duplexTypeFromJson,
  )
  final enums.DuplexType maxSpeedDuplex;
  @JsonKey(name: 'maximum_mtu')
  final int maximumMtu;
  @JsonKey(name: 'minimum_mtu')
  final int minimumMtu;
  @JsonKey(name: 'model')
  final String model;
  @JsonKey(name: 'mtu')
  final int mtu;
  @JsonKey(name: 'vendor')
  final String vendor;
  static const fromJsonFactory = _$HardwareInfoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is HardwareInfo &&
            (identical(other.autoNegotiation, autoNegotiation) ||
                const DeepCollectionEquality().equals(
                  other.autoNegotiation,
                  autoNegotiation,
                )) &&
            (identical(other.isActive, isActive) ||
                const DeepCollectionEquality().equals(
                  other.isActive,
                  isActive,
                )) &&
            (identical(other.isLoopback, isLoopback) ||
                const DeepCollectionEquality().equals(
                  other.isLoopback,
                  isLoopback,
                )) &&
            (identical(other.macAddress, macAddress) ||
                const DeepCollectionEquality().equals(
                  other.macAddress,
                  macAddress,
                )) &&
            (identical(other.maxSpeed, maxSpeed) ||
                const DeepCollectionEquality().equals(
                  other.maxSpeed,
                  maxSpeed,
                )) &&
            (identical(other.maxSpeedDuplex, maxSpeedDuplex) ||
                const DeepCollectionEquality().equals(
                  other.maxSpeedDuplex,
                  maxSpeedDuplex,
                )) &&
            (identical(other.maximumMtu, maximumMtu) ||
                const DeepCollectionEquality().equals(
                  other.maximumMtu,
                  maximumMtu,
                )) &&
            (identical(other.minimumMtu, minimumMtu) ||
                const DeepCollectionEquality().equals(
                  other.minimumMtu,
                  minimumMtu,
                )) &&
            (identical(other.model, model) ||
                const DeepCollectionEquality().equals(other.model, model)) &&
            (identical(other.mtu, mtu) ||
                const DeepCollectionEquality().equals(other.mtu, mtu)) &&
            (identical(other.vendor, vendor) ||
                const DeepCollectionEquality().equals(other.vendor, vendor)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(autoNegotiation) ^
      const DeepCollectionEquality().hash(isActive) ^
      const DeepCollectionEquality().hash(isLoopback) ^
      const DeepCollectionEquality().hash(macAddress) ^
      const DeepCollectionEquality().hash(maxSpeed) ^
      const DeepCollectionEquality().hash(maxSpeedDuplex) ^
      const DeepCollectionEquality().hash(maximumMtu) ^
      const DeepCollectionEquality().hash(minimumMtu) ^
      const DeepCollectionEquality().hash(model) ^
      const DeepCollectionEquality().hash(mtu) ^
      const DeepCollectionEquality().hash(vendor) ^
      runtimeType.hashCode;
}

extension $HardwareInfoExtension on HardwareInfo {
  HardwareInfo copyWith({
    bool? autoNegotiation,
    bool? isActive,
    bool? isLoopback,
    String? macAddress,
    int? maxSpeed,
    enums.DuplexType? maxSpeedDuplex,
    int? maximumMtu,
    int? minimumMtu,
    String? model,
    int? mtu,
    String? vendor,
  }) {
    return HardwareInfo(
      autoNegotiation: autoNegotiation ?? this.autoNegotiation,
      isActive: isActive ?? this.isActive,
      isLoopback: isLoopback ?? this.isLoopback,
      macAddress: macAddress ?? this.macAddress,
      maxSpeed: maxSpeed ?? this.maxSpeed,
      maxSpeedDuplex: maxSpeedDuplex ?? this.maxSpeedDuplex,
      maximumMtu: maximumMtu ?? this.maximumMtu,
      minimumMtu: minimumMtu ?? this.minimumMtu,
      model: model ?? this.model,
      mtu: mtu ?? this.mtu,
      vendor: vendor ?? this.vendor,
    );
  }

  HardwareInfo copyWithWrapped({
    Wrapped<bool>? autoNegotiation,
    Wrapped<bool>? isActive,
    Wrapped<bool>? isLoopback,
    Wrapped<String>? macAddress,
    Wrapped<int>? maxSpeed,
    Wrapped<enums.DuplexType>? maxSpeedDuplex,
    Wrapped<int>? maximumMtu,
    Wrapped<int>? minimumMtu,
    Wrapped<String>? model,
    Wrapped<int>? mtu,
    Wrapped<String>? vendor,
  }) {
    return HardwareInfo(
      autoNegotiation: (autoNegotiation != null
          ? autoNegotiation.value
          : this.autoNegotiation),
      isActive: (isActive != null ? isActive.value : this.isActive),
      isLoopback: (isLoopback != null ? isLoopback.value : this.isLoopback),
      macAddress: (macAddress != null ? macAddress.value : this.macAddress),
      maxSpeed: (maxSpeed != null ? maxSpeed.value : this.maxSpeed),
      maxSpeedDuplex: (maxSpeedDuplex != null
          ? maxSpeedDuplex.value
          : this.maxSpeedDuplex),
      maximumMtu: (maximumMtu != null ? maximumMtu.value : this.maximumMtu),
      minimumMtu: (minimumMtu != null ? minimumMtu.value : this.minimumMtu),
      model: (model != null ? model.value : this.model),
      mtu: (mtu != null ? mtu.value : this.mtu),
      vendor: (vendor != null ? vendor.value : this.vendor),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Hello {
  const Hello({required this.world});

  factory Hello.fromJson(Map<String, dynamic> json) => _$HelloFromJson(json);

  static const toJsonFactory = _$HelloToJson;
  Map<String, dynamic> toJson() => _$HelloToJson(this);

  @JsonKey(name: 'world')
  final String world;
  static const fromJsonFactory = _$HelloFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Hello &&
            (identical(other.world, world) ||
                const DeepCollectionEquality().equals(other.world, world)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(world) ^ runtimeType.hashCode;
}

extension $HelloExtension on Hello {
  Hello copyWith({String? world}) {
    return Hello(world: world ?? this.world);
  }

  Hello copyWithWrapped({Wrapped<String>? world}) {
    return Hello(world: (world != null ? world.value : this.world));
  }
}

@JsonSerializable(explicitToJson: true)
class IPv4Config {
  const IPv4Config({
    this.gateway,
    required this.ipv4,
    this.nameServers,
    required this.netmask,
  });

  factory IPv4Config.fromJson(Map<String, dynamic> json) =>
      _$IPv4ConfigFromJson(json);

  static const toJsonFactory = _$IPv4ConfigToJson;
  Map<String, dynamic> toJson() => _$IPv4ConfigToJson(this);

  @JsonKey(name: 'gateway')
  final String? gateway;
  @JsonKey(name: 'ipv4')
  final String ipv4;
  @JsonKey(name: 'name_servers', defaultValue: <String>[])
  final List<String>? nameServers;
  @JsonKey(name: 'netmask')
  final String netmask;
  static const fromJsonFactory = _$IPv4ConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is IPv4Config &&
            (identical(other.gateway, gateway) ||
                const DeepCollectionEquality().equals(
                  other.gateway,
                  gateway,
                )) &&
            (identical(other.ipv4, ipv4) ||
                const DeepCollectionEquality().equals(other.ipv4, ipv4)) &&
            (identical(other.nameServers, nameServers) ||
                const DeepCollectionEquality().equals(
                  other.nameServers,
                  nameServers,
                )) &&
            (identical(other.netmask, netmask) ||
                const DeepCollectionEquality().equals(other.netmask, netmask)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(gateway) ^
      const DeepCollectionEquality().hash(ipv4) ^
      const DeepCollectionEquality().hash(nameServers) ^
      const DeepCollectionEquality().hash(netmask) ^
      runtimeType.hashCode;
}

extension $IPv4ConfigExtension on IPv4Config {
  IPv4Config copyWith({
    String? gateway,
    String? ipv4,
    List<String>? nameServers,
    String? netmask,
  }) {
    return IPv4Config(
      gateway: gateway ?? this.gateway,
      ipv4: ipv4 ?? this.ipv4,
      nameServers: nameServers ?? this.nameServers,
      netmask: netmask ?? this.netmask,
    );
  }

  IPv4Config copyWithWrapped({
    Wrapped<String?>? gateway,
    Wrapped<String>? ipv4,
    Wrapped<List<String>?>? nameServers,
    Wrapped<String>? netmask,
  }) {
    return IPv4Config(
      gateway: (gateway != null ? gateway.value : this.gateway),
      ipv4: (ipv4 != null ? ipv4.value : this.ipv4),
      nameServers: (nameServers != null ? nameServers.value : this.nameServers),
      netmask: (netmask != null ? netmask.value : this.netmask),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class IPv4Info {
  const IPv4Info({
    required this.broadcast,
    required this.dhcp,
    required this.gateway,
    required this.ipv4,
    required this.nameServers,
    required this.netmask,
  });

  factory IPv4Info.fromJson(Map<String, dynamic> json) =>
      _$IPv4InfoFromJson(json);

  static const toJsonFactory = _$IPv4InfoToJson;
  Map<String, dynamic> toJson() => _$IPv4InfoToJson(this);

  @JsonKey(name: 'broadcast')
  final String broadcast;
  @JsonKey(name: 'dhcp')
  final bool dhcp;
  @JsonKey(name: 'gateway')
  final String gateway;
  @JsonKey(name: 'ipv4')
  final String ipv4;
  @JsonKey(name: 'name_servers', defaultValue: <String>[])
  final List<String> nameServers;
  @JsonKey(name: 'netmask')
  final String netmask;
  static const fromJsonFactory = _$IPv4InfoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is IPv4Info &&
            (identical(other.broadcast, broadcast) ||
                const DeepCollectionEquality().equals(
                  other.broadcast,
                  broadcast,
                )) &&
            (identical(other.dhcp, dhcp) ||
                const DeepCollectionEquality().equals(other.dhcp, dhcp)) &&
            (identical(other.gateway, gateway) ||
                const DeepCollectionEquality().equals(
                  other.gateway,
                  gateway,
                )) &&
            (identical(other.ipv4, ipv4) ||
                const DeepCollectionEquality().equals(other.ipv4, ipv4)) &&
            (identical(other.nameServers, nameServers) ||
                const DeepCollectionEquality().equals(
                  other.nameServers,
                  nameServers,
                )) &&
            (identical(other.netmask, netmask) ||
                const DeepCollectionEquality().equals(other.netmask, netmask)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(broadcast) ^
      const DeepCollectionEquality().hash(dhcp) ^
      const DeepCollectionEquality().hash(gateway) ^
      const DeepCollectionEquality().hash(ipv4) ^
      const DeepCollectionEquality().hash(nameServers) ^
      const DeepCollectionEquality().hash(netmask) ^
      runtimeType.hashCode;
}

extension $IPv4InfoExtension on IPv4Info {
  IPv4Info copyWith({
    String? broadcast,
    bool? dhcp,
    String? gateway,
    String? ipv4,
    List<String>? nameServers,
    String? netmask,
  }) {
    return IPv4Info(
      broadcast: broadcast ?? this.broadcast,
      dhcp: dhcp ?? this.dhcp,
      gateway: gateway ?? this.gateway,
      ipv4: ipv4 ?? this.ipv4,
      nameServers: nameServers ?? this.nameServers,
      netmask: netmask ?? this.netmask,
    );
  }

  IPv4Info copyWithWrapped({
    Wrapped<String>? broadcast,
    Wrapped<bool>? dhcp,
    Wrapped<String>? gateway,
    Wrapped<String>? ipv4,
    Wrapped<List<String>>? nameServers,
    Wrapped<String>? netmask,
  }) {
    return IPv4Info(
      broadcast: (broadcast != null ? broadcast.value : this.broadcast),
      dhcp: (dhcp != null ? dhcp.value : this.dhcp),
      gateway: (gateway != null ? gateway.value : this.gateway),
      ipv4: (ipv4 != null ? ipv4.value : this.ipv4),
      nameServers: (nameServers != null ? nameServers.value : this.nameServers),
      netmask: (netmask != null ? netmask.value : this.netmask),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class InterfaceConfig {
  const InterfaceConfig({required this.dhcp, this.ipv4Config, this.mtu});

  factory InterfaceConfig.fromJson(Map<String, dynamic> json) =>
      _$InterfaceConfigFromJson(json);

  static const toJsonFactory = _$InterfaceConfigToJson;
  Map<String, dynamic> toJson() => _$InterfaceConfigToJson(this);

  @JsonKey(name: 'dhcp')
  final bool dhcp;
  @JsonKey(name: 'ipv4_config')
  final IPv4Config? ipv4Config;
  @JsonKey(name: 'mtu')
  final int? mtu;
  static const fromJsonFactory = _$InterfaceConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is InterfaceConfig &&
            (identical(other.dhcp, dhcp) ||
                const DeepCollectionEquality().equals(other.dhcp, dhcp)) &&
            (identical(other.ipv4Config, ipv4Config) ||
                const DeepCollectionEquality().equals(
                  other.ipv4Config,
                  ipv4Config,
                )) &&
            (identical(other.mtu, mtu) ||
                const DeepCollectionEquality().equals(other.mtu, mtu)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(dhcp) ^
      const DeepCollectionEquality().hash(ipv4Config) ^
      const DeepCollectionEquality().hash(mtu) ^
      runtimeType.hashCode;
}

extension $InterfaceConfigExtension on InterfaceConfig {
  InterfaceConfig copyWith({bool? dhcp, IPv4Config? ipv4Config, int? mtu}) {
    return InterfaceConfig(
      dhcp: dhcp ?? this.dhcp,
      ipv4Config: ipv4Config ?? this.ipv4Config,
      mtu: mtu ?? this.mtu,
    );
  }

  InterfaceConfig copyWithWrapped({
    Wrapped<bool>? dhcp,
    Wrapped<IPv4Config?>? ipv4Config,
    Wrapped<int?>? mtu,
  }) {
    return InterfaceConfig(
      dhcp: (dhcp != null ? dhcp.value : this.dhcp),
      ipv4Config: (ipv4Config != null ? ipv4Config.value : this.ipv4Config),
      mtu: (mtu != null ? mtu.value : this.mtu),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Invite {
  const Invite({required this.creationDate, required this.email});

  factory Invite.fromJson(Map<String, dynamic> json) => _$InviteFromJson(json);

  static const toJsonFactory = _$InviteToJson;
  Map<String, dynamic> toJson() => _$InviteToJson(this);

  @JsonKey(name: 'creation_date')
  final DateTime creationDate;
  @JsonKey(name: 'email')
  final String email;
  static const fromJsonFactory = _$InviteFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Invite &&
            (identical(other.creationDate, creationDate) ||
                const DeepCollectionEquality().equals(
                  other.creationDate,
                  creationDate,
                )) &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(creationDate) ^
      const DeepCollectionEquality().hash(email) ^
      runtimeType.hashCode;
}

extension $InviteExtension on Invite {
  Invite copyWith({DateTime? creationDate, String? email}) {
    return Invite(
      creationDate: creationDate ?? this.creationDate,
      email: email ?? this.email,
    );
  }

  Invite copyWithWrapped({
    Wrapped<DateTime>? creationDate,
    Wrapped<String>? email,
  }) {
    return Invite(
      creationDate: (creationDate != null
          ? creationDate.value
          : this.creationDate),
      email: (email != null ? email.value : this.email),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class LinkInfo {
  const LinkInfo({
    required this.duplex,
    required this.link,
    required this.speed,
  });

  factory LinkInfo.fromJson(Map<String, dynamic> json) =>
      _$LinkInfoFromJson(json);

  static const toJsonFactory = _$LinkInfoToJson;
  Map<String, dynamic> toJson() => _$LinkInfoToJson(this);

  @JsonKey(
    name: 'duplex',
    toJson: duplexTypeToJson,
    fromJson: duplexTypeFromJson,
  )
  final enums.DuplexType duplex;
  @JsonKey(name: 'link', toJson: linkStatusToJson, fromJson: linkStatusFromJson)
  final enums.LinkStatus link;
  @JsonKey(name: 'speed')
  final int speed;
  static const fromJsonFactory = _$LinkInfoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is LinkInfo &&
            (identical(other.duplex, duplex) ||
                const DeepCollectionEquality().equals(other.duplex, duplex)) &&
            (identical(other.link, link) ||
                const DeepCollectionEquality().equals(other.link, link)) &&
            (identical(other.speed, speed) ||
                const DeepCollectionEquality().equals(other.speed, speed)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(duplex) ^
      const DeepCollectionEquality().hash(link) ^
      const DeepCollectionEquality().hash(speed) ^
      runtimeType.hashCode;
}

extension $LinkInfoExtension on LinkInfo {
  LinkInfo copyWith({
    enums.DuplexType? duplex,
    enums.LinkStatus? link,
    int? speed,
  }) {
    return LinkInfo(
      duplex: duplex ?? this.duplex,
      link: link ?? this.link,
      speed: speed ?? this.speed,
    );
  }

  LinkInfo copyWithWrapped({
    Wrapped<enums.DuplexType>? duplex,
    Wrapped<enums.LinkStatus>? link,
    Wrapped<int>? speed,
  }) {
    return LinkInfo(
      duplex: (duplex != null ? duplex.value : this.duplex),
      link: (link != null ? link.value : this.link),
      speed: (speed != null ? speed.value : this.speed),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class NTPConfig {
  const NTPConfig({
    required this.enabled,
    required this.servers,
    required this.synchronized,
  });

  factory NTPConfig.fromJson(Map<String, dynamic> json) =>
      _$NTPConfigFromJson(json);

  static const toJsonFactory = _$NTPConfigToJson;
  Map<String, dynamic> toJson() => _$NTPConfigToJson(this);

  @JsonKey(name: 'enabled')
  final bool enabled;
  @JsonKey(name: 'servers', defaultValue: <String>[])
  final List<String> servers;
  @JsonKey(name: 'synchronized')
  final bool synchronized;
  static const fromJsonFactory = _$NTPConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NTPConfig &&
            (identical(other.enabled, enabled) ||
                const DeepCollectionEquality().equals(
                  other.enabled,
                  enabled,
                )) &&
            (identical(other.servers, servers) ||
                const DeepCollectionEquality().equals(
                  other.servers,
                  servers,
                )) &&
            (identical(other.synchronized, synchronized) ||
                const DeepCollectionEquality().equals(
                  other.synchronized,
                  synchronized,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(enabled) ^
      const DeepCollectionEquality().hash(servers) ^
      const DeepCollectionEquality().hash(synchronized) ^
      runtimeType.hashCode;
}

extension $NTPConfigExtension on NTPConfig {
  NTPConfig copyWith({
    bool? enabled,
    List<String>? servers,
    bool? synchronized,
  }) {
    return NTPConfig(
      enabled: enabled ?? this.enabled,
      servers: servers ?? this.servers,
      synchronized: synchronized ?? this.synchronized,
    );
  }

  NTPConfig copyWithWrapped({
    Wrapped<bool>? enabled,
    Wrapped<List<String>>? servers,
    Wrapped<bool>? synchronized,
  }) {
    return NTPConfig(
      enabled: (enabled != null ? enabled.value : this.enabled),
      servers: (servers != null ? servers.value : this.servers),
      synchronized: (synchronized != null
          ? synchronized.value
          : this.synchronized),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class NetworkInterface {
  const NetworkInterface({
    required this.hardwareInfo,
    this.ipv4Info,
    this.linkInfo,
    required this.name,
    required this.type,
  });

  factory NetworkInterface.fromJson(Map<String, dynamic> json) =>
      _$NetworkInterfaceFromJson(json);

  static const toJsonFactory = _$NetworkInterfaceToJson;
  Map<String, dynamic> toJson() => _$NetworkInterfaceToJson(this);

  @JsonKey(name: 'hardware_info')
  final HardwareInfo hardwareInfo;
  @JsonKey(name: 'ipv4_info')
  final IPv4Info? ipv4Info;
  @JsonKey(name: 'link_info')
  final LinkInfo? linkInfo;
  @JsonKey(name: 'name')
  final String name;
  @JsonKey(
    name: 'type',
    toJson: networkInterfaceTypeToJson,
    fromJson: networkInterfaceTypeFromJson,
  )
  final enums.NetworkInterfaceType type;
  static const fromJsonFactory = _$NetworkInterfaceFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is NetworkInterface &&
            (identical(other.hardwareInfo, hardwareInfo) ||
                const DeepCollectionEquality().equals(
                  other.hardwareInfo,
                  hardwareInfo,
                )) &&
            (identical(other.ipv4Info, ipv4Info) ||
                const DeepCollectionEquality().equals(
                  other.ipv4Info,
                  ipv4Info,
                )) &&
            (identical(other.linkInfo, linkInfo) ||
                const DeepCollectionEquality().equals(
                  other.linkInfo,
                  linkInfo,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(hardwareInfo) ^
      const DeepCollectionEquality().hash(ipv4Info) ^
      const DeepCollectionEquality().hash(linkInfo) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(type) ^
      runtimeType.hashCode;
}

extension $NetworkInterfaceExtension on NetworkInterface {
  NetworkInterface copyWith({
    HardwareInfo? hardwareInfo,
    IPv4Info? ipv4Info,
    LinkInfo? linkInfo,
    String? name,
    enums.NetworkInterfaceType? type,
  }) {
    return NetworkInterface(
      hardwareInfo: hardwareInfo ?? this.hardwareInfo,
      ipv4Info: ipv4Info ?? this.ipv4Info,
      linkInfo: linkInfo ?? this.linkInfo,
      name: name ?? this.name,
      type: type ?? this.type,
    );
  }

  NetworkInterface copyWithWrapped({
    Wrapped<HardwareInfo>? hardwareInfo,
    Wrapped<IPv4Info?>? ipv4Info,
    Wrapped<LinkInfo?>? linkInfo,
    Wrapped<String>? name,
    Wrapped<enums.NetworkInterfaceType>? type,
  }) {
    return NetworkInterface(
      hardwareInfo: (hardwareInfo != null
          ? hardwareInfo.value
          : this.hardwareInfo),
      ipv4Info: (ipv4Info != null ? ipv4Info.value : this.ipv4Info),
      linkInfo: (linkInfo != null ? linkInfo.value : this.linkInfo),
      name: (name != null ? name.value : this.name),
      type: (type != null ? type.value : this.type),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Oobe {
  const Oobe({required this.done});

  factory Oobe.fromJson(Map<String, dynamic> json) => _$OobeFromJson(json);

  static const toJsonFactory = _$OobeToJson;
  Map<String, dynamic> toJson() => _$OobeToJson(this);

  @JsonKey(name: 'done')
  final bool done;
  static const fromJsonFactory = _$OobeFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Oobe &&
            (identical(other.done, done) ||
                const DeepCollectionEquality().equals(other.done, done)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(done) ^ runtimeType.hashCode;
}

extension $OobeExtension on Oobe {
  Oobe copyWith({bool? done}) {
    return Oobe(done: done ?? this.done);
  }

  Oobe copyWithWrapped({Wrapped<bool>? done}) {
    return Oobe(done: (done != null ? done.value : this.done));
  }
}

@JsonSerializable(explicitToJson: true)
class SMTPConfig {
  const SMTPConfig({
    required this.password,
    required this.port,
    required this.server,
    required this.user,
  });

  factory SMTPConfig.fromJson(Map<String, dynamic> json) =>
      _$SMTPConfigFromJson(json);

  static const toJsonFactory = _$SMTPConfigToJson;
  Map<String, dynamic> toJson() => _$SMTPConfigToJson(this);

  @JsonKey(name: 'password')
  final String password;
  @JsonKey(name: 'port')
  final int port;
  @JsonKey(name: 'server')
  final String server;
  @JsonKey(name: 'user')
  final String user;
  static const fromJsonFactory = _$SMTPConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is SMTPConfig &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )) &&
            (identical(other.port, port) ||
                const DeepCollectionEquality().equals(other.port, port)) &&
            (identical(other.server, server) ||
                const DeepCollectionEquality().equals(other.server, server)) &&
            (identical(other.user, user) ||
                const DeepCollectionEquality().equals(other.user, user)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(password) ^
      const DeepCollectionEquality().hash(port) ^
      const DeepCollectionEquality().hash(server) ^
      const DeepCollectionEquality().hash(user) ^
      runtimeType.hashCode;
}

extension $SMTPConfigExtension on SMTPConfig {
  SMTPConfig copyWith({
    String? password,
    int? port,
    String? server,
    String? user,
  }) {
    return SMTPConfig(
      password: password ?? this.password,
      port: port ?? this.port,
      server: server ?? this.server,
      user: user ?? this.user,
    );
  }

  SMTPConfig copyWithWrapped({
    Wrapped<String>? password,
    Wrapped<int>? port,
    Wrapped<String>? server,
    Wrapped<String>? user,
  }) {
    return SMTPConfig(
      password: (password != null ? password.value : this.password),
      port: (port != null ? port.value : this.port),
      server: (server != null ? server.value : this.server),
      user: (user != null ? user.value : this.user),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Status {
  const Status({required this.oobe, required this.apps, required this.state});

  factory Status.fromJson(Map<String, dynamic> json) => _$StatusFromJson(json);

  static const toJsonFactory = _$StatusToJson;
  Map<String, dynamic> toJson() => _$StatusToJson(this);

  @JsonKey(name: 'OOBE')
  final Oobe oobe;
  @JsonKey(name: 'apps')
  final AppStatus apps;
  @JsonKey(
    name: 'state',
    toJson: statusStateToJson,
    fromJson: statusStateFromJson,
  )
  final enums.StatusState state;
  static const fromJsonFactory = _$StatusFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Status &&
            (identical(other.oobe, oobe) ||
                const DeepCollectionEquality().equals(other.oobe, oobe)) &&
            (identical(other.apps, apps) ||
                const DeepCollectionEquality().equals(other.apps, apps)) &&
            (identical(other.state, state) ||
                const DeepCollectionEquality().equals(other.state, state)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(oobe) ^
      const DeepCollectionEquality().hash(apps) ^
      const DeepCollectionEquality().hash(state) ^
      runtimeType.hashCode;
}

extension $StatusExtension on Status {
  Status copyWith({Oobe? oobe, AppStatus? apps, enums.StatusState? state}) {
    return Status(
      oobe: oobe ?? this.oobe,
      apps: apps ?? this.apps,
      state: state ?? this.state,
    );
  }

  Status copyWithWrapped({
    Wrapped<Oobe>? oobe,
    Wrapped<AppStatus>? apps,
    Wrapped<enums.StatusState>? state,
  }) {
    return Status(
      oobe: (oobe != null ? oobe.value : this.oobe),
      apps: (apps != null ? apps.value : this.apps),
      state: (state != null ? state.value : this.state),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class TimeConfig {
  const TimeConfig({
    required this.date,
    required this.ntp,
    required this.timezone,
  });

  factory TimeConfig.fromJson(Map<String, dynamic> json) =>
      _$TimeConfigFromJson(json);

  static const toJsonFactory = _$TimeConfigToJson;
  Map<String, dynamic> toJson() => _$TimeConfigToJson(this);

  @JsonKey(name: 'date')
  final DateTime date;
  @JsonKey(name: 'ntp')
  final NTPConfig ntp;
  @JsonKey(name: 'timezone')
  final String timezone;
  static const fromJsonFactory = _$TimeConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TimeConfig &&
            (identical(other.date, date) ||
                const DeepCollectionEquality().equals(other.date, date)) &&
            (identical(other.ntp, ntp) ||
                const DeepCollectionEquality().equals(other.ntp, ntp)) &&
            (identical(other.timezone, timezone) ||
                const DeepCollectionEquality().equals(
                  other.timezone,
                  timezone,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(date) ^
      const DeepCollectionEquality().hash(ntp) ^
      const DeepCollectionEquality().hash(timezone) ^
      runtimeType.hashCode;
}

extension $TimeConfigExtension on TimeConfig {
  TimeConfig copyWith({DateTime? date, NTPConfig? ntp, String? timezone}) {
    return TimeConfig(
      date: date ?? this.date,
      ntp: ntp ?? this.ntp,
      timezone: timezone ?? this.timezone,
    );
  }

  TimeConfig copyWithWrapped({
    Wrapped<DateTime>? date,
    Wrapped<NTPConfig>? ntp,
    Wrapped<String>? timezone,
  }) {
    return TimeConfig(
      date: (date != null ? date.value : this.date),
      ntp: (ntp != null ? ntp.value : this.ntp),
      timezone: (timezone != null ? timezone.value : this.timezone),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Update {
  const Update({required this.type, required this.version});

  factory Update.fromJson(Map<String, dynamic> json) => _$UpdateFromJson(json);

  static const toJsonFactory = _$UpdateToJson;
  Map<String, dynamic> toJson() => _$UpdateToJson(this);

  @JsonKey(name: 'type', toJson: updateTypeToJson, fromJson: updateTypeFromJson)
  final enums.UpdateType type;
  @JsonKey(name: 'version')
  final String version;
  static const fromJsonFactory = _$UpdateFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Update &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)) &&
            (identical(other.version, version) ||
                const DeepCollectionEquality().equals(other.version, version)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(type) ^
      const DeepCollectionEquality().hash(version) ^
      runtimeType.hashCode;
}

extension $UpdateExtension on Update {
  Update copyWith({enums.UpdateType? type, String? version}) {
    return Update(type: type ?? this.type, version: version ?? this.version);
  }

  Update copyWithWrapped({
    Wrapped<enums.UpdateType>? type,
    Wrapped<String>? version,
  }) {
    return Update(
      type: (type != null ? type.value : this.type),
      version: (version != null ? version.value : this.version),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UpdateInfo {
  const UpdateInfo({required this.currentVersion, required this.targetVersion});

  factory UpdateInfo.fromJson(Map<String, dynamic> json) =>
      _$UpdateInfoFromJson(json);

  static const toJsonFactory = _$UpdateInfoToJson;
  Map<String, dynamic> toJson() => _$UpdateInfoToJson(this);

  @JsonKey(name: 'current_version')
  final String currentVersion;
  @JsonKey(name: 'target_version')
  final String targetVersion;
  static const fromJsonFactory = _$UpdateInfoFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UpdateInfo &&
            (identical(other.currentVersion, currentVersion) ||
                const DeepCollectionEquality().equals(
                  other.currentVersion,
                  currentVersion,
                )) &&
            (identical(other.targetVersion, targetVersion) ||
                const DeepCollectionEquality().equals(
                  other.targetVersion,
                  targetVersion,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(currentVersion) ^
      const DeepCollectionEquality().hash(targetVersion) ^
      runtimeType.hashCode;
}

extension $UpdateInfoExtension on UpdateInfo {
  UpdateInfo copyWith({String? currentVersion, String? targetVersion}) {
    return UpdateInfo(
      currentVersion: currentVersion ?? this.currentVersion,
      targetVersion: targetVersion ?? this.targetVersion,
    );
  }

  UpdateInfo copyWithWrapped({
    Wrapped<String>? currentVersion,
    Wrapped<String>? targetVersion,
  }) {
    return UpdateInfo(
      currentVersion: (currentVersion != null
          ? currentVersion.value
          : this.currentVersion),
      targetVersion: (targetVersion != null
          ? targetVersion.value
          : this.targetVersion),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UpdateLabel {
  const UpdateLabel({required this.enabled, required this.name});

  factory UpdateLabel.fromJson(Map<String, dynamic> json) =>
      _$UpdateLabelFromJson(json);

  static const toJsonFactory = _$UpdateLabelToJson;
  Map<String, dynamic> toJson() => _$UpdateLabelToJson(this);

  @JsonKey(name: 'enabled')
  final bool enabled;
  @JsonKey(name: 'name')
  final String name;
  static const fromJsonFactory = _$UpdateLabelFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UpdateLabel &&
            (identical(other.enabled, enabled) ||
                const DeepCollectionEquality().equals(
                  other.enabled,
                  enabled,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(enabled) ^
      const DeepCollectionEquality().hash(name) ^
      runtimeType.hashCode;
}

extension $UpdateLabelExtension on UpdateLabel {
  UpdateLabel copyWith({bool? enabled, String? name}) {
    return UpdateLabel(
      enabled: enabled ?? this.enabled,
      name: name ?? this.name,
    );
  }

  UpdateLabel copyWithWrapped({Wrapped<bool>? enabled, Wrapped<String>? name}) {
    return UpdateLabel(
      enabled: (enabled != null ? enabled.value : this.enabled),
      name: (name != null ? name.value : this.name),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UpdateProgress {
  const UpdateProgress({required this.progress});

  factory UpdateProgress.fromJson(Map<String, dynamic> json) =>
      _$UpdateProgressFromJson(json);

  static const toJsonFactory = _$UpdateProgressToJson;
  Map<String, dynamic> toJson() => _$UpdateProgressToJson(this);

  @JsonKey(name: 'progress')
  final int progress;
  static const fromJsonFactory = _$UpdateProgressFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UpdateProgress &&
            (identical(other.progress, progress) ||
                const DeepCollectionEquality().equals(
                  other.progress,
                  progress,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(progress) ^ runtimeType.hashCode;
}

extension $UpdateProgressExtension on UpdateProgress {
  UpdateProgress copyWith({int? progress}) {
    return UpdateProgress(progress: progress ?? this.progress);
  }

  UpdateProgress copyWithWrapped({Wrapped<int>? progress}) {
    return UpdateProgress(
      progress: (progress != null ? progress.value : this.progress),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class User {
  const User({
    required this.email,
    required this.error,
    required this.isAdmin,
    required this.isOwner,
    required this.name,
    required this.userId,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);

  static const toJsonFactory = _$UserToJson;
  Map<String, dynamic> toJson() => _$UserToJson(this);

  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'error')
  final String error;
  @JsonKey(name: 'is_admin')
  final bool isAdmin;
  @JsonKey(name: 'is_owner')
  final bool isOwner;
  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'user_id')
  final String userId;
  static const fromJsonFactory = _$UserFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is User &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.error, error) ||
                const DeepCollectionEquality().equals(other.error, error)) &&
            (identical(other.isAdmin, isAdmin) ||
                const DeepCollectionEquality().equals(
                  other.isAdmin,
                  isAdmin,
                )) &&
            (identical(other.isOwner, isOwner) ||
                const DeepCollectionEquality().equals(
                  other.isOwner,
                  isOwner,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.userId, userId) ||
                const DeepCollectionEquality().equals(other.userId, userId)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(error) ^
      const DeepCollectionEquality().hash(isAdmin) ^
      const DeepCollectionEquality().hash(isOwner) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(userId) ^
      runtimeType.hashCode;
}

extension $UserExtension on User {
  User copyWith({
    String? email,
    String? error,
    bool? isAdmin,
    bool? isOwner,
    String? name,
    String? userId,
  }) {
    return User(
      email: email ?? this.email,
      error: error ?? this.error,
      isAdmin: isAdmin ?? this.isAdmin,
      isOwner: isOwner ?? this.isOwner,
      name: name ?? this.name,
      userId: userId ?? this.userId,
    );
  }

  User copyWithWrapped({
    Wrapped<String>? email,
    Wrapped<String>? error,
    Wrapped<bool>? isAdmin,
    Wrapped<bool>? isOwner,
    Wrapped<String>? name,
    Wrapped<String>? userId,
  }) {
    return User(
      email: (email != null ? email.value : this.email),
      error: (error != null ? error.value : this.error),
      isAdmin: (isAdmin != null ? isAdmin.value : this.isAdmin),
      isOwner: (isOwner != null ? isOwner.value : this.isOwner),
      name: (name != null ? name.value : this.name),
      userId: (userId != null ? userId.value : this.userId),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class WifiConfig {
  const WifiConfig({required this.ssid, required this.password});

  factory WifiConfig.fromJson(Map<String, dynamic> json) =>
      _$WifiConfigFromJson(json);

  static const toJsonFactory = _$WifiConfigToJson;
  Map<String, dynamic> toJson() => _$WifiConfigToJson(this);

  @JsonKey(name: 'SSID')
  final String ssid;
  @JsonKey(name: 'password')
  final String password;
  static const fromJsonFactory = _$WifiConfigFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is WifiConfig &&
            (identical(other.ssid, ssid) ||
                const DeepCollectionEquality().equals(other.ssid, ssid)) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(ssid) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $WifiConfigExtension on WifiConfig {
  WifiConfig copyWith({String? ssid, String? password}) {
    return WifiConfig(
      ssid: ssid ?? this.ssid,
      password: password ?? this.password,
    );
  }

  WifiConfig copyWithWrapped({
    Wrapped<String>? ssid,
    Wrapped<String>? password,
  }) {
    return WifiConfig(
      ssid: (ssid != null ? ssid.value : this.ssid),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AuthLoginPost$RequestBody {
  const AuthLoginPost$RequestBody({
    required this.email,
    required this.password,
  });

  factory AuthLoginPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$AuthLoginPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$AuthLoginPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$AuthLoginPost$RequestBodyToJson(this);

  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'password')
  final String password;
  static const fromJsonFactory = _$AuthLoginPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AuthLoginPost$RequestBody &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $AuthLoginPost$RequestBodyExtension on AuthLoginPost$RequestBody {
  AuthLoginPost$RequestBody copyWith({String? email, String? password}) {
    return AuthLoginPost$RequestBody(
      email: email ?? this.email,
      password: password ?? this.password,
    );
  }

  AuthLoginPost$RequestBody copyWithWrapped({
    Wrapped<String>? email,
    Wrapped<String>? password,
  }) {
    return AuthLoginPost$RequestBody(
      email: (email != null ? email.value : this.email),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AuthLogoutPost$RequestBody {
  const AuthLogoutPost$RequestBody({required this.refreshToken});

  factory AuthLogoutPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$AuthLogoutPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$AuthLogoutPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$AuthLogoutPost$RequestBodyToJson(this);

  @JsonKey(name: 'refresh_token')
  final String refreshToken;
  static const fromJsonFactory = _$AuthLogoutPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AuthLogoutPost$RequestBody &&
            (identical(other.refreshToken, refreshToken) ||
                const DeepCollectionEquality().equals(
                  other.refreshToken,
                  refreshToken,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(refreshToken) ^ runtimeType.hashCode;
}

extension $AuthLogoutPost$RequestBodyExtension on AuthLogoutPost$RequestBody {
  AuthLogoutPost$RequestBody copyWith({String? refreshToken}) {
    return AuthLogoutPost$RequestBody(
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  AuthLogoutPost$RequestBody copyWithWrapped({Wrapped<String>? refreshToken}) {
    return AuthLogoutPost$RequestBody(
      refreshToken: (refreshToken != null
          ? refreshToken.value
          : this.refreshToken),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class AuthRefreshPost$RequestBody {
  const AuthRefreshPost$RequestBody({
    required this.grantType,
    required this.refreshToken,
  });

  factory AuthRefreshPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$AuthRefreshPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$AuthRefreshPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$AuthRefreshPost$RequestBodyToJson(this);

  @JsonKey(
    name: 'grant_type',
    toJson: authRefreshPost$RequestBodyGrantTypeToJson,
    fromJson: authRefreshPost$RequestBodyGrantTypeFromJson,
  )
  final enums.AuthRefreshPost$RequestBodyGrantType grantType;
  @JsonKey(name: 'refresh_token')
  final String refreshToken;
  static const fromJsonFactory = _$AuthRefreshPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is AuthRefreshPost$RequestBody &&
            (identical(other.grantType, grantType) ||
                const DeepCollectionEquality().equals(
                  other.grantType,
                  grantType,
                )) &&
            (identical(other.refreshToken, refreshToken) ||
                const DeepCollectionEquality().equals(
                  other.refreshToken,
                  refreshToken,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(grantType) ^
      const DeepCollectionEquality().hash(refreshToken) ^
      runtimeType.hashCode;
}

extension $AuthRefreshPost$RequestBodyExtension on AuthRefreshPost$RequestBody {
  AuthRefreshPost$RequestBody copyWith({
    enums.AuthRefreshPost$RequestBodyGrantType? grantType,
    String? refreshToken,
  }) {
    return AuthRefreshPost$RequestBody(
      grantType: grantType ?? this.grantType,
      refreshToken: refreshToken ?? this.refreshToken,
    );
  }

  AuthRefreshPost$RequestBody copyWithWrapped({
    Wrapped<enums.AuthRefreshPost$RequestBodyGrantType>? grantType,
    Wrapped<String>? refreshToken,
  }) {
    return AuthRefreshPost$RequestBody(
      grantType: (grantType != null ? grantType.value : this.grantType),
      refreshToken: (refreshToken != null
          ? refreshToken.value
          : this.refreshToken),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class PowerPost$RequestBody {
  const PowerPost$RequestBody({required this.action});

  factory PowerPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$PowerPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$PowerPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$PowerPost$RequestBodyToJson(this);

  @JsonKey(
    name: 'action',
    toJson: powerOffTypeToJson,
    fromJson: powerOffTypeFromJson,
  )
  final enums.PowerOffType action;
  static const fromJsonFactory = _$PowerPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PowerPost$RequestBody &&
            (identical(other.action, action) ||
                const DeepCollectionEquality().equals(other.action, action)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(action) ^ runtimeType.hashCode;
}

extension $PowerPost$RequestBodyExtension on PowerPost$RequestBody {
  PowerPost$RequestBody copyWith({enums.PowerOffType? action}) {
    return PowerPost$RequestBody(action: action ?? this.action);
  }

  PowerPost$RequestBody copyWithWrapped({Wrapped<enums.PowerOffType>? action}) {
    return PowerPost$RequestBody(
      action: (action != null ? action.value : this.action),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class ResetPost$RequestBody {
  const ResetPost$RequestBody({this.provisioningPassword, required this.type});

  factory ResetPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$ResetPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$ResetPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$ResetPost$RequestBodyToJson(this);

  @JsonKey(name: 'provisioning_password')
  final String? provisioningPassword;
  @JsonKey(name: 'type', toJson: resetTypeToJson, fromJson: resetTypeFromJson)
  final enums.ResetType type;
  static const fromJsonFactory = _$ResetPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ResetPost$RequestBody &&
            (identical(other.provisioningPassword, provisioningPassword) ||
                const DeepCollectionEquality().equals(
                  other.provisioningPassword,
                  provisioningPassword,
                )) &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(provisioningPassword) ^
      const DeepCollectionEquality().hash(type) ^
      runtimeType.hashCode;
}

extension $ResetPost$RequestBodyExtension on ResetPost$RequestBody {
  ResetPost$RequestBody copyWith({
    String? provisioningPassword,
    enums.ResetType? type,
  }) {
    return ResetPost$RequestBody(
      provisioningPassword: provisioningPassword ?? this.provisioningPassword,
      type: type ?? this.type,
    );
  }

  ResetPost$RequestBody copyWithWrapped({
    Wrapped<String?>? provisioningPassword,
    Wrapped<enums.ResetType>? type,
  }) {
    return ResetPost$RequestBody(
      provisioningPassword: (provisioningPassword != null
          ? provisioningPassword.value
          : this.provisioningPassword),
      type: (type != null ? type.value : this.type),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UsersIdPut$RequestBody {
  const UsersIdPut$RequestBody({
    this.email,
    this.isAdmin,
    this.name,
    this.oldPassword,
    this.password,
  });

  factory UsersIdPut$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$UsersIdPut$RequestBodyFromJson(json);

  static const toJsonFactory = _$UsersIdPut$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$UsersIdPut$RequestBodyToJson(this);

  @JsonKey(name: 'email')
  final String? email;
  @JsonKey(name: 'is_admin')
  final bool? isAdmin;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'old_password')
  final String? oldPassword;
  @JsonKey(name: 'password')
  final String? password;
  static const fromJsonFactory = _$UsersIdPut$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersIdPut$RequestBody &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.isAdmin, isAdmin) ||
                const DeepCollectionEquality().equals(
                  other.isAdmin,
                  isAdmin,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.oldPassword, oldPassword) ||
                const DeepCollectionEquality().equals(
                  other.oldPassword,
                  oldPassword,
                )) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(isAdmin) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(oldPassword) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $UsersIdPut$RequestBodyExtension on UsersIdPut$RequestBody {
  UsersIdPut$RequestBody copyWith({
    String? email,
    bool? isAdmin,
    String? name,
    String? oldPassword,
    String? password,
  }) {
    return UsersIdPut$RequestBody(
      email: email ?? this.email,
      isAdmin: isAdmin ?? this.isAdmin,
      name: name ?? this.name,
      oldPassword: oldPassword ?? this.oldPassword,
      password: password ?? this.password,
    );
  }

  UsersIdPut$RequestBody copyWithWrapped({
    Wrapped<String?>? email,
    Wrapped<bool?>? isAdmin,
    Wrapped<String?>? name,
    Wrapped<String?>? oldPassword,
    Wrapped<String?>? password,
  }) {
    return UsersIdPut$RequestBody(
      email: (email != null ? email.value : this.email),
      isAdmin: (isAdmin != null ? isAdmin.value : this.isAdmin),
      name: (name != null ? name.value : this.name),
      oldPassword: (oldPassword != null ? oldPassword.value : this.oldPassword),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UsersInvitesPost$RequestBody {
  const UsersInvitesPost$RequestBody({required this.email});

  factory UsersInvitesPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$UsersInvitesPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$UsersInvitesPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$UsersInvitesPost$RequestBodyToJson(this);

  @JsonKey(name: 'email')
  final String email;
  static const fromJsonFactory = _$UsersInvitesPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersInvitesPost$RequestBody &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^ runtimeType.hashCode;
}

extension $UsersInvitesPost$RequestBodyExtension
    on UsersInvitesPost$RequestBody {
  UsersInvitesPost$RequestBody copyWith({String? email}) {
    return UsersInvitesPost$RequestBody(email: email ?? this.email);
  }

  UsersInvitesPost$RequestBody copyWithWrapped({Wrapped<String>? email}) {
    return UsersInvitesPost$RequestBody(
      email: (email != null ? email.value : this.email),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UsersInvitesEmailPut$RequestBody {
  const UsersInvitesEmailPut$RequestBody({
    required this.confirmationCode,
    required this.name,
    required this.password,
  });

  factory UsersInvitesEmailPut$RequestBody.fromJson(
    Map<String, dynamic> json,
  ) => _$UsersInvitesEmailPut$RequestBodyFromJson(json);

  static const toJsonFactory = _$UsersInvitesEmailPut$RequestBodyToJson;
  Map<String, dynamic> toJson() =>
      _$UsersInvitesEmailPut$RequestBodyToJson(this);

  @JsonKey(name: 'confirmation_code')
  final String confirmationCode;
  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'password')
  final String password;
  static const fromJsonFactory = _$UsersInvitesEmailPut$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersInvitesEmailPut$RequestBody &&
            (identical(other.confirmationCode, confirmationCode) ||
                const DeepCollectionEquality().equals(
                  other.confirmationCode,
                  confirmationCode,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(confirmationCode) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $UsersInvitesEmailPut$RequestBodyExtension
    on UsersInvitesEmailPut$RequestBody {
  UsersInvitesEmailPut$RequestBody copyWith({
    String? confirmationCode,
    String? name,
    String? password,
  }) {
    return UsersInvitesEmailPut$RequestBody(
      confirmationCode: confirmationCode ?? this.confirmationCode,
      name: name ?? this.name,
      password: password ?? this.password,
    );
  }

  UsersInvitesEmailPut$RequestBody copyWithWrapped({
    Wrapped<String>? confirmationCode,
    Wrapped<String>? name,
    Wrapped<String>? password,
  }) {
    return UsersInvitesEmailPut$RequestBody(
      confirmationCode: (confirmationCode != null
          ? confirmationCode.value
          : this.confirmationCode),
      name: (name != null ? name.value : this.name),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UsersMePut$RequestBody {
  const UsersMePut$RequestBody({
    this.email,
    this.isAdmin,
    this.name,
    this.oldPassword,
    this.password,
  });

  factory UsersMePut$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$UsersMePut$RequestBodyFromJson(json);

  static const toJsonFactory = _$UsersMePut$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$UsersMePut$RequestBodyToJson(this);

  @JsonKey(name: 'email')
  final String? email;
  @JsonKey(name: 'is_admin')
  final bool? isAdmin;
  @JsonKey(name: 'name')
  final String? name;
  @JsonKey(name: 'old_password')
  final String? oldPassword;
  @JsonKey(name: 'password')
  final String? password;
  static const fromJsonFactory = _$UsersMePut$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersMePut$RequestBody &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.isAdmin, isAdmin) ||
                const DeepCollectionEquality().equals(
                  other.isAdmin,
                  isAdmin,
                )) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.oldPassword, oldPassword) ||
                const DeepCollectionEquality().equals(
                  other.oldPassword,
                  oldPassword,
                )) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(isAdmin) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(oldPassword) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $UsersMePut$RequestBodyExtension on UsersMePut$RequestBody {
  UsersMePut$RequestBody copyWith({
    String? email,
    bool? isAdmin,
    String? name,
    String? oldPassword,
    String? password,
  }) {
    return UsersMePut$RequestBody(
      email: email ?? this.email,
      isAdmin: isAdmin ?? this.isAdmin,
      name: name ?? this.name,
      oldPassword: oldPassword ?? this.oldPassword,
      password: password ?? this.password,
    );
  }

  UsersMePut$RequestBody copyWithWrapped({
    Wrapped<String?>? email,
    Wrapped<bool?>? isAdmin,
    Wrapped<String?>? name,
    Wrapped<String?>? oldPassword,
    Wrapped<String?>? password,
  }) {
    return UsersMePut$RequestBody(
      email: (email != null ? email.value : this.email),
      isAdmin: (isAdmin != null ? isAdmin.value : this.isAdmin),
      name: (name != null ? name.value : this.name),
      oldPassword: (oldPassword != null ? oldPassword.value : this.oldPassword),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UsersOwnerPost$RequestBody {
  const UsersOwnerPost$RequestBody({
    required this.email,
    required this.name,
    required this.password,
  });

  factory UsersOwnerPost$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$UsersOwnerPost$RequestBodyFromJson(json);

  static const toJsonFactory = _$UsersOwnerPost$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$UsersOwnerPost$RequestBodyToJson(this);

  @JsonKey(name: 'email')
  final String email;
  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'password')
  final String password;
  static const fromJsonFactory = _$UsersOwnerPost$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersOwnerPost$RequestBody &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)) &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.password, password) ||
                const DeepCollectionEquality().equals(
                  other.password,
                  password,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(email) ^
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(password) ^
      runtimeType.hashCode;
}

extension $UsersOwnerPost$RequestBodyExtension on UsersOwnerPost$RequestBody {
  UsersOwnerPost$RequestBody copyWith({
    String? email,
    String? name,
    String? password,
  }) {
    return UsersOwnerPost$RequestBody(
      email: email ?? this.email,
      name: name ?? this.name,
      password: password ?? this.password,
    );
  }

  UsersOwnerPost$RequestBody copyWithWrapped({
    Wrapped<String>? email,
    Wrapped<String>? name,
    Wrapped<String>? password,
  }) {
    return UsersOwnerPost$RequestBody(
      email: (email != null ? email.value : this.email),
      name: (name != null ? name.value : this.name),
      password: (password != null ? password.value : this.password),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class UsersOwnerPut$RequestBody {
  const UsersOwnerPut$RequestBody({required this.confirmationCode});

  factory UsersOwnerPut$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$UsersOwnerPut$RequestBodyFromJson(json);

  static const toJsonFactory = _$UsersOwnerPut$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$UsersOwnerPut$RequestBodyToJson(this);

  @JsonKey(name: 'confirmation_code')
  final String confirmationCode;
  static const fromJsonFactory = _$UsersOwnerPut$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UsersOwnerPut$RequestBody &&
            (identical(other.confirmationCode, confirmationCode) ||
                const DeepCollectionEquality().equals(
                  other.confirmationCode,
                  confirmationCode,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(confirmationCode) ^
      runtimeType.hashCode;
}

extension $UsersOwnerPut$RequestBodyExtension on UsersOwnerPut$RequestBody {
  UsersOwnerPut$RequestBody copyWith({String? confirmationCode}) {
    return UsersOwnerPut$RequestBody(
      confirmationCode: confirmationCode ?? this.confirmationCode,
    );
  }

  UsersOwnerPut$RequestBody copyWithWrapped({
    Wrapped<String>? confirmationCode,
  }) {
    return UsersOwnerPut$RequestBody(
      confirmationCode: (confirmationCode != null
          ? confirmationCode.value
          : this.confirmationCode),
    );
  }
}

String? aboutOsStateNullableToJson(enums.AboutOsState? aboutOsState) {
  return aboutOsState?.value;
}

String? aboutOsStateToJson(enums.AboutOsState aboutOsState) {
  return aboutOsState.value;
}

enums.AboutOsState aboutOsStateFromJson(
  Object? aboutOsState, [
  enums.AboutOsState? defaultValue,
]) {
  return enums.AboutOsState.values.firstWhereOrNull(
        (e) => e.value == aboutOsState,
      ) ??
      defaultValue ??
      enums.AboutOsState.swaggerGeneratedUnknown;
}

enums.AboutOsState? aboutOsStateNullableFromJson(
  Object? aboutOsState, [
  enums.AboutOsState? defaultValue,
]) {
  if (aboutOsState == null) {
    return null;
  }
  return enums.AboutOsState.values.firstWhereOrNull(
        (e) => e.value == aboutOsState,
      ) ??
      defaultValue;
}

String aboutOsStateExplodedListToJson(List<enums.AboutOsState>? aboutOsState) {
  return aboutOsState?.map((e) => e.value!).join(',') ?? '';
}

List<String> aboutOsStateListToJson(List<enums.AboutOsState>? aboutOsState) {
  if (aboutOsState == null) {
    return [];
  }

  return aboutOsState.map((e) => e.value!).toList();
}

List<enums.AboutOsState> aboutOsStateListFromJson(
  List? aboutOsState, [
  List<enums.AboutOsState>? defaultValue,
]) {
  if (aboutOsState == null) {
    return defaultValue ?? [];
  }

  return aboutOsState.map((e) => aboutOsStateFromJson(e.toString())).toList();
}

List<enums.AboutOsState>? aboutOsStateNullableListFromJson(
  List? aboutOsState, [
  List<enums.AboutOsState>? defaultValue,
]) {
  if (aboutOsState == null) {
    return defaultValue;
  }

  return aboutOsState.map((e) => aboutOsStateFromJson(e.toString())).toList();
}

String? aboutNetworkTypeNullableToJson(
  enums.AboutNetworkType? aboutNetworkType,
) {
  return aboutNetworkType?.value;
}

String? aboutNetworkTypeToJson(enums.AboutNetworkType aboutNetworkType) {
  return aboutNetworkType.value;
}

enums.AboutNetworkType aboutNetworkTypeFromJson(
  Object? aboutNetworkType, [
  enums.AboutNetworkType? defaultValue,
]) {
  return enums.AboutNetworkType.values.firstWhereOrNull(
        (e) => e.value == aboutNetworkType,
      ) ??
      defaultValue ??
      enums.AboutNetworkType.swaggerGeneratedUnknown;
}

enums.AboutNetworkType? aboutNetworkTypeNullableFromJson(
  Object? aboutNetworkType, [
  enums.AboutNetworkType? defaultValue,
]) {
  if (aboutNetworkType == null) {
    return null;
  }
  return enums.AboutNetworkType.values.firstWhereOrNull(
        (e) => e.value == aboutNetworkType,
      ) ??
      defaultValue;
}

String aboutNetworkTypeExplodedListToJson(
  List<enums.AboutNetworkType>? aboutNetworkType,
) {
  return aboutNetworkType?.map((e) => e.value!).join(',') ?? '';
}

List<String> aboutNetworkTypeListToJson(
  List<enums.AboutNetworkType>? aboutNetworkType,
) {
  if (aboutNetworkType == null) {
    return [];
  }

  return aboutNetworkType.map((e) => e.value!).toList();
}

List<enums.AboutNetworkType> aboutNetworkTypeListFromJson(
  List? aboutNetworkType, [
  List<enums.AboutNetworkType>? defaultValue,
]) {
  if (aboutNetworkType == null) {
    return defaultValue ?? [];
  }

  return aboutNetworkType
      .map((e) => aboutNetworkTypeFromJson(e.toString()))
      .toList();
}

List<enums.AboutNetworkType>? aboutNetworkTypeNullableListFromJson(
  List? aboutNetworkType, [
  List<enums.AboutNetworkType>? defaultValue,
]) {
  if (aboutNetworkType == null) {
    return defaultValue;
  }

  return aboutNetworkType
      .map((e) => aboutNetworkTypeFromJson(e.toString()))
      .toList();
}

String? authResponseTypeNullableToJson(
  enums.AuthResponseType? authResponseType,
) {
  return authResponseType?.value;
}

String? authResponseTypeToJson(enums.AuthResponseType authResponseType) {
  return authResponseType.value;
}

enums.AuthResponseType authResponseTypeFromJson(
  Object? authResponseType, [
  enums.AuthResponseType? defaultValue,
]) {
  return enums.AuthResponseType.values.firstWhereOrNull(
        (e) => e.value == authResponseType,
      ) ??
      defaultValue ??
      enums.AuthResponseType.swaggerGeneratedUnknown;
}

enums.AuthResponseType? authResponseTypeNullableFromJson(
  Object? authResponseType, [
  enums.AuthResponseType? defaultValue,
]) {
  if (authResponseType == null) {
    return null;
  }
  return enums.AuthResponseType.values.firstWhereOrNull(
        (e) => e.value == authResponseType,
      ) ??
      defaultValue;
}

String authResponseTypeExplodedListToJson(
  List<enums.AuthResponseType>? authResponseType,
) {
  return authResponseType?.map((e) => e.value!).join(',') ?? '';
}

List<String> authResponseTypeListToJson(
  List<enums.AuthResponseType>? authResponseType,
) {
  if (authResponseType == null) {
    return [];
  }

  return authResponseType.map((e) => e.value!).toList();
}

List<enums.AuthResponseType> authResponseTypeListFromJson(
  List? authResponseType, [
  List<enums.AuthResponseType>? defaultValue,
]) {
  if (authResponseType == null) {
    return defaultValue ?? [];
  }

  return authResponseType
      .map((e) => authResponseTypeFromJson(e.toString()))
      .toList();
}

List<enums.AuthResponseType>? authResponseTypeNullableListFromJson(
  List? authResponseType, [
  List<enums.AuthResponseType>? defaultValue,
]) {
  if (authResponseType == null) {
    return defaultValue;
  }

  return authResponseType
      .map((e) => authResponseTypeFromJson(e.toString()))
      .toList();
}

String? duplexTypeNullableToJson(enums.DuplexType? duplexType) {
  return duplexType?.value;
}

String? duplexTypeToJson(enums.DuplexType duplexType) {
  return duplexType.value;
}

enums.DuplexType duplexTypeFromJson(
  Object? duplexType, [
  enums.DuplexType? defaultValue,
]) {
  return enums.DuplexType.values.firstWhereOrNull(
        (e) => e.value == duplexType,
      ) ??
      defaultValue ??
      enums.DuplexType.swaggerGeneratedUnknown;
}

enums.DuplexType? duplexTypeNullableFromJson(
  Object? duplexType, [
  enums.DuplexType? defaultValue,
]) {
  if (duplexType == null) {
    return null;
  }
  return enums.DuplexType.values.firstWhereOrNull(
        (e) => e.value == duplexType,
      ) ??
      defaultValue;
}

String duplexTypeExplodedListToJson(List<enums.DuplexType>? duplexType) {
  return duplexType?.map((e) => e.value!).join(',') ?? '';
}

List<String> duplexTypeListToJson(List<enums.DuplexType>? duplexType) {
  if (duplexType == null) {
    return [];
  }

  return duplexType.map((e) => e.value!).toList();
}

List<enums.DuplexType> duplexTypeListFromJson(
  List? duplexType, [
  List<enums.DuplexType>? defaultValue,
]) {
  if (duplexType == null) {
    return defaultValue ?? [];
  }

  return duplexType.map((e) => duplexTypeFromJson(e.toString())).toList();
}

List<enums.DuplexType>? duplexTypeNullableListFromJson(
  List? duplexType, [
  List<enums.DuplexType>? defaultValue,
]) {
  if (duplexType == null) {
    return defaultValue;
  }

  return duplexType.map((e) => duplexTypeFromJson(e.toString())).toList();
}

String? linkStatusNullableToJson(enums.LinkStatus? linkStatus) {
  return linkStatus?.value;
}

String? linkStatusToJson(enums.LinkStatus linkStatus) {
  return linkStatus.value;
}

enums.LinkStatus linkStatusFromJson(
  Object? linkStatus, [
  enums.LinkStatus? defaultValue,
]) {
  return enums.LinkStatus.values.firstWhereOrNull(
        (e) => e.value == linkStatus,
      ) ??
      defaultValue ??
      enums.LinkStatus.swaggerGeneratedUnknown;
}

enums.LinkStatus? linkStatusNullableFromJson(
  Object? linkStatus, [
  enums.LinkStatus? defaultValue,
]) {
  if (linkStatus == null) {
    return null;
  }
  return enums.LinkStatus.values.firstWhereOrNull(
        (e) => e.value == linkStatus,
      ) ??
      defaultValue;
}

String linkStatusExplodedListToJson(List<enums.LinkStatus>? linkStatus) {
  return linkStatus?.map((e) => e.value!).join(',') ?? '';
}

List<String> linkStatusListToJson(List<enums.LinkStatus>? linkStatus) {
  if (linkStatus == null) {
    return [];
  }

  return linkStatus.map((e) => e.value!).toList();
}

List<enums.LinkStatus> linkStatusListFromJson(
  List? linkStatus, [
  List<enums.LinkStatus>? defaultValue,
]) {
  if (linkStatus == null) {
    return defaultValue ?? [];
  }

  return linkStatus.map((e) => linkStatusFromJson(e.toString())).toList();
}

List<enums.LinkStatus>? linkStatusNullableListFromJson(
  List? linkStatus, [
  List<enums.LinkStatus>? defaultValue,
]) {
  if (linkStatus == null) {
    return defaultValue;
  }

  return linkStatus.map((e) => linkStatusFromJson(e.toString())).toList();
}

String? networkInterfaceTypeNullableToJson(
  enums.NetworkInterfaceType? networkInterfaceType,
) {
  return networkInterfaceType?.value;
}

String? networkInterfaceTypeToJson(
  enums.NetworkInterfaceType networkInterfaceType,
) {
  return networkInterfaceType.value;
}

enums.NetworkInterfaceType networkInterfaceTypeFromJson(
  Object? networkInterfaceType, [
  enums.NetworkInterfaceType? defaultValue,
]) {
  return enums.NetworkInterfaceType.values.firstWhereOrNull(
        (e) => e.value == networkInterfaceType,
      ) ??
      defaultValue ??
      enums.NetworkInterfaceType.swaggerGeneratedUnknown;
}

enums.NetworkInterfaceType? networkInterfaceTypeNullableFromJson(
  Object? networkInterfaceType, [
  enums.NetworkInterfaceType? defaultValue,
]) {
  if (networkInterfaceType == null) {
    return null;
  }
  return enums.NetworkInterfaceType.values.firstWhereOrNull(
        (e) => e.value == networkInterfaceType,
      ) ??
      defaultValue;
}

String networkInterfaceTypeExplodedListToJson(
  List<enums.NetworkInterfaceType>? networkInterfaceType,
) {
  return networkInterfaceType?.map((e) => e.value!).join(',') ?? '';
}

List<String> networkInterfaceTypeListToJson(
  List<enums.NetworkInterfaceType>? networkInterfaceType,
) {
  if (networkInterfaceType == null) {
    return [];
  }

  return networkInterfaceType.map((e) => e.value!).toList();
}

List<enums.NetworkInterfaceType> networkInterfaceTypeListFromJson(
  List? networkInterfaceType, [
  List<enums.NetworkInterfaceType>? defaultValue,
]) {
  if (networkInterfaceType == null) {
    return defaultValue ?? [];
  }

  return networkInterfaceType
      .map((e) => networkInterfaceTypeFromJson(e.toString()))
      .toList();
}

List<enums.NetworkInterfaceType>? networkInterfaceTypeNullableListFromJson(
  List? networkInterfaceType, [
  List<enums.NetworkInterfaceType>? defaultValue,
]) {
  if (networkInterfaceType == null) {
    return defaultValue;
  }

  return networkInterfaceType
      .map((e) => networkInterfaceTypeFromJson(e.toString()))
      .toList();
}

String? powerOffTypeNullableToJson(enums.PowerOffType? powerOffType) {
  return powerOffType?.value;
}

String? powerOffTypeToJson(enums.PowerOffType powerOffType) {
  return powerOffType.value;
}

enums.PowerOffType powerOffTypeFromJson(
  Object? powerOffType, [
  enums.PowerOffType? defaultValue,
]) {
  return enums.PowerOffType.values.firstWhereOrNull(
        (e) => e.value == powerOffType,
      ) ??
      defaultValue ??
      enums.PowerOffType.swaggerGeneratedUnknown;
}

enums.PowerOffType? powerOffTypeNullableFromJson(
  Object? powerOffType, [
  enums.PowerOffType? defaultValue,
]) {
  if (powerOffType == null) {
    return null;
  }
  return enums.PowerOffType.values.firstWhereOrNull(
        (e) => e.value == powerOffType,
      ) ??
      defaultValue;
}

String powerOffTypeExplodedListToJson(List<enums.PowerOffType>? powerOffType) {
  return powerOffType?.map((e) => e.value!).join(',') ?? '';
}

List<String> powerOffTypeListToJson(List<enums.PowerOffType>? powerOffType) {
  if (powerOffType == null) {
    return [];
  }

  return powerOffType.map((e) => e.value!).toList();
}

List<enums.PowerOffType> powerOffTypeListFromJson(
  List? powerOffType, [
  List<enums.PowerOffType>? defaultValue,
]) {
  if (powerOffType == null) {
    return defaultValue ?? [];
  }

  return powerOffType.map((e) => powerOffTypeFromJson(e.toString())).toList();
}

List<enums.PowerOffType>? powerOffTypeNullableListFromJson(
  List? powerOffType, [
  List<enums.PowerOffType>? defaultValue,
]) {
  if (powerOffType == null) {
    return defaultValue;
  }

  return powerOffType.map((e) => powerOffTypeFromJson(e.toString())).toList();
}

String? resetTypeNullableToJson(enums.ResetType? resetType) {
  return resetType?.value;
}

String? resetTypeToJson(enums.ResetType resetType) {
  return resetType.value;
}

enums.ResetType resetTypeFromJson(
  Object? resetType, [
  enums.ResetType? defaultValue,
]) {
  return enums.ResetType.values.firstWhereOrNull((e) => e.value == resetType) ??
      defaultValue ??
      enums.ResetType.swaggerGeneratedUnknown;
}

enums.ResetType? resetTypeNullableFromJson(
  Object? resetType, [
  enums.ResetType? defaultValue,
]) {
  if (resetType == null) {
    return null;
  }
  return enums.ResetType.values.firstWhereOrNull((e) => e.value == resetType) ??
      defaultValue;
}

String resetTypeExplodedListToJson(List<enums.ResetType>? resetType) {
  return resetType?.map((e) => e.value!).join(',') ?? '';
}

List<String> resetTypeListToJson(List<enums.ResetType>? resetType) {
  if (resetType == null) {
    return [];
  }

  return resetType.map((e) => e.value!).toList();
}

List<enums.ResetType> resetTypeListFromJson(
  List? resetType, [
  List<enums.ResetType>? defaultValue,
]) {
  if (resetType == null) {
    return defaultValue ?? [];
  }

  return resetType.map((e) => resetTypeFromJson(e.toString())).toList();
}

List<enums.ResetType>? resetTypeNullableListFromJson(
  List? resetType, [
  List<enums.ResetType>? defaultValue,
]) {
  if (resetType == null) {
    return defaultValue;
  }

  return resetType.map((e) => resetTypeFromJson(e.toString())).toList();
}

String? statusStateNullableToJson(enums.StatusState? statusState) {
  return statusState?.value;
}

String? statusStateToJson(enums.StatusState statusState) {
  return statusState.value;
}

enums.StatusState statusStateFromJson(
  Object? statusState, [
  enums.StatusState? defaultValue,
]) {
  return enums.StatusState.values.firstWhereOrNull(
        (e) => e.value == statusState,
      ) ??
      defaultValue ??
      enums.StatusState.swaggerGeneratedUnknown;
}

enums.StatusState? statusStateNullableFromJson(
  Object? statusState, [
  enums.StatusState? defaultValue,
]) {
  if (statusState == null) {
    return null;
  }
  return enums.StatusState.values.firstWhereOrNull(
        (e) => e.value == statusState,
      ) ??
      defaultValue;
}

String statusStateExplodedListToJson(List<enums.StatusState>? statusState) {
  return statusState?.map((e) => e.value!).join(',') ?? '';
}

List<String> statusStateListToJson(List<enums.StatusState>? statusState) {
  if (statusState == null) {
    return [];
  }

  return statusState.map((e) => e.value!).toList();
}

List<enums.StatusState> statusStateListFromJson(
  List? statusState, [
  List<enums.StatusState>? defaultValue,
]) {
  if (statusState == null) {
    return defaultValue ?? [];
  }

  return statusState.map((e) => statusStateFromJson(e.toString())).toList();
}

List<enums.StatusState>? statusStateNullableListFromJson(
  List? statusState, [
  List<enums.StatusState>? defaultValue,
]) {
  if (statusState == null) {
    return defaultValue;
  }

  return statusState.map((e) => statusStateFromJson(e.toString())).toList();
}

String? updateTypeNullableToJson(enums.UpdateType? updateType) {
  return updateType?.value;
}

String? updateTypeToJson(enums.UpdateType updateType) {
  return updateType.value;
}

enums.UpdateType updateTypeFromJson(
  Object? updateType, [
  enums.UpdateType? defaultValue,
]) {
  return enums.UpdateType.values.firstWhereOrNull(
        (e) => e.value == updateType,
      ) ??
      defaultValue ??
      enums.UpdateType.swaggerGeneratedUnknown;
}

enums.UpdateType? updateTypeNullableFromJson(
  Object? updateType, [
  enums.UpdateType? defaultValue,
]) {
  if (updateType == null) {
    return null;
  }
  return enums.UpdateType.values.firstWhereOrNull(
        (e) => e.value == updateType,
      ) ??
      defaultValue;
}

String updateTypeExplodedListToJson(List<enums.UpdateType>? updateType) {
  return updateType?.map((e) => e.value!).join(',') ?? '';
}

List<String> updateTypeListToJson(List<enums.UpdateType>? updateType) {
  if (updateType == null) {
    return [];
  }

  return updateType.map((e) => e.value!).toList();
}

List<enums.UpdateType> updateTypeListFromJson(
  List? updateType, [
  List<enums.UpdateType>? defaultValue,
]) {
  if (updateType == null) {
    return defaultValue ?? [];
  }

  return updateType.map((e) => updateTypeFromJson(e.toString())).toList();
}

List<enums.UpdateType>? updateTypeNullableListFromJson(
  List? updateType, [
  List<enums.UpdateType>? defaultValue,
]) {
  if (updateType == null) {
    return defaultValue;
  }

  return updateType.map((e) => updateTypeFromJson(e.toString())).toList();
}

String? authRefreshPost$RequestBodyGrantTypeNullableToJson(
  enums.AuthRefreshPost$RequestBodyGrantType?
  authRefreshPost$RequestBodyGrantType,
) {
  return authRefreshPost$RequestBodyGrantType?.value;
}

String? authRefreshPost$RequestBodyGrantTypeToJson(
  enums.AuthRefreshPost$RequestBodyGrantType
  authRefreshPost$RequestBodyGrantType,
) {
  return authRefreshPost$RequestBodyGrantType.value;
}

enums.AuthRefreshPost$RequestBodyGrantType
authRefreshPost$RequestBodyGrantTypeFromJson(
  Object? authRefreshPost$RequestBodyGrantType, [
  enums.AuthRefreshPost$RequestBodyGrantType? defaultValue,
]) {
  return enums.AuthRefreshPost$RequestBodyGrantType.values.firstWhereOrNull(
        (e) => e.value == authRefreshPost$RequestBodyGrantType,
      ) ??
      defaultValue ??
      enums.AuthRefreshPost$RequestBodyGrantType.swaggerGeneratedUnknown;
}

enums.AuthRefreshPost$RequestBodyGrantType?
authRefreshPost$RequestBodyGrantTypeNullableFromJson(
  Object? authRefreshPost$RequestBodyGrantType, [
  enums.AuthRefreshPost$RequestBodyGrantType? defaultValue,
]) {
  if (authRefreshPost$RequestBodyGrantType == null) {
    return null;
  }
  return enums.AuthRefreshPost$RequestBodyGrantType.values.firstWhereOrNull(
        (e) => e.value == authRefreshPost$RequestBodyGrantType,
      ) ??
      defaultValue;
}

String authRefreshPost$RequestBodyGrantTypeExplodedListToJson(
  List<enums.AuthRefreshPost$RequestBodyGrantType>?
  authRefreshPost$RequestBodyGrantType,
) {
  return authRefreshPost$RequestBodyGrantType?.map((e) => e.value!).join(',') ??
      '';
}

List<String> authRefreshPost$RequestBodyGrantTypeListToJson(
  List<enums.AuthRefreshPost$RequestBodyGrantType>?
  authRefreshPost$RequestBodyGrantType,
) {
  if (authRefreshPost$RequestBodyGrantType == null) {
    return [];
  }

  return authRefreshPost$RequestBodyGrantType.map((e) => e.value!).toList();
}

List<enums.AuthRefreshPost$RequestBodyGrantType>
authRefreshPost$RequestBodyGrantTypeListFromJson(
  List? authRefreshPost$RequestBodyGrantType, [
  List<enums.AuthRefreshPost$RequestBodyGrantType>? defaultValue,
]) {
  if (authRefreshPost$RequestBodyGrantType == null) {
    return defaultValue ?? [];
  }

  return authRefreshPost$RequestBodyGrantType
      .map((e) => authRefreshPost$RequestBodyGrantTypeFromJson(e.toString()))
      .toList();
}

List<enums.AuthRefreshPost$RequestBodyGrantType>?
authRefreshPost$RequestBodyGrantTypeNullableListFromJson(
  List? authRefreshPost$RequestBodyGrantType, [
  List<enums.AuthRefreshPost$RequestBodyGrantType>? defaultValue,
]) {
  if (authRefreshPost$RequestBodyGrantType == null) {
    return defaultValue;
  }

  return authRefreshPost$RequestBodyGrantType
      .map((e) => authRefreshPost$RequestBodyGrantTypeFromJson(e.toString()))
      .toList();
}

typedef $JsonFactory<T> = T Function(Map<String, dynamic> json);

class $CustomJsonDecoder {
  $CustomJsonDecoder(this.factories);

  final Map<Type, $JsonFactory> factories;

  dynamic decode<T>(dynamic entity) {
    if (entity is Iterable) {
      return _decodeList<T>(entity);
    }

    if (entity is T) {
      return entity;
    }

    if (isTypeOf<T, Map>()) {
      return entity;
    }

    if (isTypeOf<T, Iterable>()) {
      return entity;
    }

    if (entity is Map<String, dynamic>) {
      return _decodeMap<T>(entity);
    }

    return entity;
  }

  T _decodeMap<T>(Map<String, dynamic> values) {
    final jsonFactory = factories[T];
    if (jsonFactory == null || jsonFactory is! $JsonFactory<T>) {
      return throw "Could not find factory for type $T. Is '$T: $T.fromJsonFactory' included in the CustomJsonDecoder instance creation in bootstrapper.dart?";
    }

    return jsonFactory(values);
  }

  List<T> _decodeList<T>(Iterable values) =>
      values.where((v) => v != null).map<T>((v) => decode<T>(v) as T).toList();
}

class $JsonSerializableConverter extends chopper.JsonConverter {
  @override
  FutureOr<chopper.Response<ResultType>> convertResponse<ResultType, Item>(
    chopper.Response response,
  ) async {
    if (response.bodyString.isEmpty) {
      // In rare cases, when let's say 204 (no content) is returned -
      // we cannot decode the missing json with the result type specified
      return chopper.Response(response.base, null, error: response.error);
    }

    if (ResultType == String) {
      return response.copyWith();
    }

    if (ResultType == DateTime) {
      return response.copyWith(
        body:
            DateTime.parse((response.body as String).replaceAll('"', ''))
                as ResultType,
      );
    }

    final jsonRes = await super.convertResponse(response);
    return jsonRes.copyWith<ResultType>(
      body: $jsonDecoder.decode<Item>(jsonRes.body) as ResultType,
    );
  }
}

final $jsonDecoder = $CustomJsonDecoder(generatedMapping);

// ignore: unused_element
String? _dateToJson(DateTime? date) {
  if (date == null) {
    return null;
  }

  final year = date.year.toString();
  final month = date.month < 10 ? '0${date.month}' : date.month.toString();
  final day = date.day < 10 ? '0${date.day}' : date.day.toString();

  return '$year-$month-$day';
}

class Wrapped<T> {
  final T value;
  const Wrapped.value(this.value);
}
