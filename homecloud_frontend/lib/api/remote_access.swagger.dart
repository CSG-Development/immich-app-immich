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
import 'remote_access.enums.swagger.dart' as enums;
import 'remote_access.metadata.swagger.dart';
export 'remote_access.enums.swagger.dart';

part 'remote_access.swagger.chopper.dart';
part 'remote_access.swagger.g.dart';

// **************************************************************************
// SwaggerChopperGenerator
// **************************************************************************

@ChopperApi()
abstract class RemoteAccess extends ChopperService {
  static RemoteAccess create({
    ChopperClient? client,
    http.Client? httpClient,
    Authenticator? authenticator,
    ErrorConverter? errorConverter,
    Converter? converter,
    Uri? baseUrl,
    List<Interceptor>? interceptors,
  }) {
    if (client != null) {
      return _$RemoteAccess(client);
    }

    final newClient = ChopperClient(
      services: [_$RemoteAccess()],
      converter: converter ?? $JsonSerializableConverter(),
      interceptors: interceptors ?? [],
      client: httpClient,
      authenticator: authenticator,
      errorConverter: errorConverter,
      baseUrl: baseUrl ?? Uri.parse('http://'),
    );
    return _$RemoteAccess(newClient);
  }

  ///Initiate client authentication
  ///@param type Type of user identifier. Only email for now.
  Future<chopper.Response<InitiateResponse$Response>> clientV1AuthInitiatePost({
    required enums.ClientV1AuthInitiatePostType? type,
    required Code$RequestBody? body,
  }) {
    generatedMapping.putIfAbsent(
      InitiateResponse$Response,
      () => InitiateResponse$Response.fromJsonFactory,
    );

    return _clientV1AuthInitiatePost(type: type?.value?.toString(), body: body);
  }

  ///Initiate client authentication
  ///@param type Type of user identifier. Only email for now.
  @POST(path: '/client/v1/auth/initiate', optionalBody: true)
  Future<chopper.Response<InitiateResponse$Response>>
  _clientV1AuthInitiatePost({
    @Query('type') required String? type,
    @Body() required Code$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Renew a JWT access token using a refresh token
  ///@param refresh_token Refresh token
  Future<chopper.Response<TokenResponse$Response>> clientV1AuthRefreshGet({
    required String? refreshToken,
  }) {
    generatedMapping.putIfAbsent(
      TokenResponse$Response,
      () => TokenResponse$Response.fromJsonFactory,
    );

    return _clientV1AuthRefreshGet(refreshToken: refreshToken);
  }

  ///Renew a JWT access token using a refresh token
  ///@param refresh_token Refresh token
  @GET(path: '/client/v1/auth/refresh')
  Future<chopper.Response<TokenResponse$Response>> _clientV1AuthRefreshGet({
    @Query('refresh_token') required String? refreshToken,
    @chopper.Tag()
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
  });

  ///Obtain a JWT access token
  ///@param type Type of user identifier. Only email for now.
  Future<chopper.Response<TokenResponse$Response>> clientV1AuthTokenPost({
    required enums.ClientV1AuthTokenPostType? type,
    required Validate$RequestBody? body,
  }) {
    generatedMapping.putIfAbsent(
      TokenResponse$Response,
      () => TokenResponse$Response.fromJsonFactory,
    );

    return _clientV1AuthTokenPost(type: type?.value?.toString(), body: body);
  }

  ///Obtain a JWT access token
  ///@param type Type of user identifier. Only email for now.
  @POST(path: '/client/v1/auth/token', optionalBody: true)
  Future<chopper.Response<TokenResponse$Response>> _clientV1AuthTokenPost({
    @Query('type') required String? type,
    @Body() required Validate$RequestBody? body,
    @chopper.Tag()
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
  });

  ///Retrieve the list of devices a user has access to
  Future<chopper.Response<List<Device>>> clientV1DevicesGet() {
    generatedMapping.putIfAbsent(Device, () => Device.fromJsonFactory);

    return _clientV1DevicesGet();
  }

  ///Retrieve the list of devices a user has access to
  @GET(path: '/client/v1/devices')
  Future<chopper.Response<List<Device>>> _clientV1DevicesGet({
    @chopper.Tag()
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
  });

  ///Get information about a device
  ///@param deviceID Device identifier
  Future<chopper.Response<DevicePaths>> clientV1DevicesDeviceIDGet({
    required String? deviceID,
  }) {
    generatedMapping.putIfAbsent(
      DevicePaths,
      () => DevicePaths.fromJsonFactory,
    );

    return _clientV1DevicesDeviceIDGet(deviceID: deviceID);
  }

  ///Get information about a device
  ///@param deviceID Device identifier
  @GET(path: '/client/v1/devices/{deviceID}')
  Future<chopper.Response<DevicePaths>> _clientV1DevicesDeviceIDGet({
    @Path('deviceID') required String? deviceID,
    @chopper.Tag()
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
  });
}

@JsonSerializable(explicitToJson: true)
class Device {
  const Device({
    required this.certificateCommonName,
    required this.friendlyName,
    required this.hostname,
    required this.seagateDeviceID,
  });

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);

  static const toJsonFactory = _$DeviceToJson;
  Map<String, dynamic> toJson() => _$DeviceToJson(this);

  @JsonKey(name: 'certificateCommonName')
  final String certificateCommonName;
  @JsonKey(name: 'friendlyName')
  final String friendlyName;
  @JsonKey(name: 'hostname')
  final String hostname;
  @JsonKey(name: 'seagateDeviceID')
  final String seagateDeviceID;
  static const fromJsonFactory = _$DeviceFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Device &&
            (identical(other.certificateCommonName, certificateCommonName) ||
                const DeepCollectionEquality().equals(
                  other.certificateCommonName,
                  certificateCommonName,
                )) &&
            (identical(other.friendlyName, friendlyName) ||
                const DeepCollectionEquality().equals(
                  other.friendlyName,
                  friendlyName,
                )) &&
            (identical(other.hostname, hostname) ||
                const DeepCollectionEquality().equals(
                  other.hostname,
                  hostname,
                )) &&
            (identical(other.seagateDeviceID, seagateDeviceID) ||
                const DeepCollectionEquality().equals(
                  other.seagateDeviceID,
                  seagateDeviceID,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(certificateCommonName) ^
      const DeepCollectionEquality().hash(friendlyName) ^
      const DeepCollectionEquality().hash(hostname) ^
      const DeepCollectionEquality().hash(seagateDeviceID) ^
      runtimeType.hashCode;
}

extension $DeviceExtension on Device {
  Device copyWith({
    String? certificateCommonName,
    String? friendlyName,
    String? hostname,
    String? seagateDeviceID,
  }) {
    return Device(
      certificateCommonName:
          certificateCommonName ?? this.certificateCommonName,
      friendlyName: friendlyName ?? this.friendlyName,
      hostname: hostname ?? this.hostname,
      seagateDeviceID: seagateDeviceID ?? this.seagateDeviceID,
    );
  }

  Device copyWithWrapped({
    Wrapped<String>? certificateCommonName,
    Wrapped<String>? friendlyName,
    Wrapped<String>? hostname,
    Wrapped<String>? seagateDeviceID,
  }) {
    return Device(
      certificateCommonName: (certificateCommonName != null
          ? certificateCommonName.value
          : this.certificateCommonName),
      friendlyName: (friendlyName != null
          ? friendlyName.value
          : this.friendlyName),
      hostname: (hostname != null ? hostname.value : this.hostname),
      seagateDeviceID: (seagateDeviceID != null
          ? seagateDeviceID.value
          : this.seagateDeviceID),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DevicePaths {
  const DevicePaths({required this.paths, required this.seagateDeviceID});

  factory DevicePaths.fromJson(Map<String, dynamic> json) =>
      _$DevicePathsFromJson(json);

  static const toJsonFactory = _$DevicePathsToJson;
  Map<String, dynamic> toJson() => _$DevicePathsToJson(this);

  @JsonKey(name: 'paths', defaultValue: <DevicePath>[])
  final List<DevicePath> paths;
  @JsonKey(name: 'seagateDeviceID')
  final String seagateDeviceID;
  static const fromJsonFactory = _$DevicePathsFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DevicePaths &&
            (identical(other.paths, paths) ||
                const DeepCollectionEquality().equals(other.paths, paths)) &&
            (identical(other.seagateDeviceID, seagateDeviceID) ||
                const DeepCollectionEquality().equals(
                  other.seagateDeviceID,
                  seagateDeviceID,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(paths) ^
      const DeepCollectionEquality().hash(seagateDeviceID) ^
      runtimeType.hashCode;
}

extension $DevicePathsExtension on DevicePaths {
  DevicePaths copyWith({List<DevicePath>? paths, String? seagateDeviceID}) {
    return DevicePaths(
      paths: paths ?? this.paths,
      seagateDeviceID: seagateDeviceID ?? this.seagateDeviceID,
    );
  }

  DevicePaths copyWithWrapped({
    Wrapped<List<DevicePath>>? paths,
    Wrapped<String>? seagateDeviceID,
  }) {
    return DevicePaths(
      paths: (paths != null ? paths.value : this.paths),
      seagateDeviceID: (seagateDeviceID != null
          ? seagateDeviceID.value
          : this.seagateDeviceID),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Error {
  const Error({required this.name, required this.stacktrace, this.reason});

  factory Error.fromJson(Map<String, dynamic> json) => _$ErrorFromJson(json);

  static const toJsonFactory = _$ErrorToJson;
  Map<String, dynamic> toJson() => _$ErrorToJson(this);

  @JsonKey(name: 'name')
  final String name;
  @JsonKey(name: 'stacktrace')
  final String stacktrace;
  @JsonKey(name: 'reason')
  final String? reason;
  static const fromJsonFactory = _$ErrorFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Error &&
            (identical(other.name, name) ||
                const DeepCollectionEquality().equals(other.name, name)) &&
            (identical(other.stacktrace, stacktrace) ||
                const DeepCollectionEquality().equals(
                  other.stacktrace,
                  stacktrace,
                )) &&
            (identical(other.reason, reason) ||
                const DeepCollectionEquality().equals(other.reason, reason)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(name) ^
      const DeepCollectionEquality().hash(stacktrace) ^
      const DeepCollectionEquality().hash(reason) ^
      runtimeType.hashCode;
}

extension $ErrorExtension on Error {
  Error copyWith({String? name, String? stacktrace, String? reason}) {
    return Error(
      name: name ?? this.name,
      stacktrace: stacktrace ?? this.stacktrace,
      reason: reason ?? this.reason,
    );
  }

  Error copyWithWrapped({
    Wrapped<String>? name,
    Wrapped<String>? stacktrace,
    Wrapped<String?>? reason,
  }) {
    return Error(
      name: (name != null ? name.value : this.name),
      stacktrace: (stacktrace != null ? stacktrace.value : this.stacktrace),
      reason: (reason != null ? reason.value : this.reason),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class DevicePath {
  const DevicePath({required this.address, this.port, required this.type});

  factory DevicePath.fromJson(Map<String, dynamic> json) =>
      _$DevicePathFromJson(json);

  static const toJsonFactory = _$DevicePathToJson;
  Map<String, dynamic> toJson() => _$DevicePathToJson(this);

  @JsonKey(name: 'address')
  final String address;
  @JsonKey(name: 'port')
  final int? port;
  @JsonKey(
    name: 'type',
    toJson: devicePathTypeToJson,
    fromJson: devicePathTypeFromJson,
  )
  final enums.DevicePathType type;
  static const fromJsonFactory = _$DevicePathFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is DevicePath &&
            (identical(other.address, address) ||
                const DeepCollectionEquality().equals(
                  other.address,
                  address,
                )) &&
            (identical(other.port, port) ||
                const DeepCollectionEquality().equals(other.port, port)) &&
            (identical(other.type, type) ||
                const DeepCollectionEquality().equals(other.type, type)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(address) ^
      const DeepCollectionEquality().hash(port) ^
      const DeepCollectionEquality().hash(type) ^
      runtimeType.hashCode;
}

extension $DevicePathExtension on DevicePath {
  DevicePath copyWith({
    String? address,
    int? port,
    enums.DevicePathType? type,
  }) {
    return DevicePath(
      address: address ?? this.address,
      port: port ?? this.port,
      type: type ?? this.type,
    );
  }

  DevicePath copyWithWrapped({
    Wrapped<String>? address,
    Wrapped<int?>? port,
    Wrapped<enums.DevicePathType>? type,
  }) {
    return DevicePath(
      address: (address != null ? address.value : this.address),
      port: (port != null ? port.value : this.port),
      type: (type != null ? type.value : this.type),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class InitiateResponse$Response {
  const InitiateResponse$Response({required this.reference});

  factory InitiateResponse$Response.fromJson(Map<String, dynamic> json) =>
      _$InitiateResponse$ResponseFromJson(json);

  static const toJsonFactory = _$InitiateResponse$ResponseToJson;
  Map<String, dynamic> toJson() => _$InitiateResponse$ResponseToJson(this);

  @JsonKey(name: 'reference')
  final String reference;
  static const fromJsonFactory = _$InitiateResponse$ResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is InitiateResponse$Response &&
            (identical(other.reference, reference) ||
                const DeepCollectionEquality().equals(
                  other.reference,
                  reference,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(reference) ^ runtimeType.hashCode;
}

extension $InitiateResponse$ResponseExtension on InitiateResponse$Response {
  InitiateResponse$Response copyWith({String? reference}) {
    return InitiateResponse$Response(reference: reference ?? this.reference);
  }

  InitiateResponse$Response copyWithWrapped({Wrapped<String>? reference}) {
    return InitiateResponse$Response(
      reference: (reference != null ? reference.value : this.reference),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class TokenResponse$Response {
  const TokenResponse$Response({
    required this.accessToken,
    required this.expiresIn,
    required this.refreshToken,
    required this.tokenType,
  });

  factory TokenResponse$Response.fromJson(Map<String, dynamic> json) =>
      _$TokenResponse$ResponseFromJson(json);

  static const toJsonFactory = _$TokenResponse$ResponseToJson;
  Map<String, dynamic> toJson() => _$TokenResponse$ResponseToJson(this);

  @JsonKey(name: 'accessToken')
  final String accessToken;
  @JsonKey(name: 'expiresIn')
  final int expiresIn;
  @JsonKey(name: 'refreshToken')
  final String refreshToken;
  @JsonKey(name: 'tokenType')
  final String tokenType;
  static const fromJsonFactory = _$TokenResponse$ResponseFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is TokenResponse$Response &&
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
            (identical(other.tokenType, tokenType) ||
                const DeepCollectionEquality().equals(
                  other.tokenType,
                  tokenType,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(accessToken) ^
      const DeepCollectionEquality().hash(expiresIn) ^
      const DeepCollectionEquality().hash(refreshToken) ^
      const DeepCollectionEquality().hash(tokenType) ^
      runtimeType.hashCode;
}

extension $TokenResponse$ResponseExtension on TokenResponse$Response {
  TokenResponse$Response copyWith({
    String? accessToken,
    int? expiresIn,
    String? refreshToken,
    String? tokenType,
  }) {
    return TokenResponse$Response(
      accessToken: accessToken ?? this.accessToken,
      expiresIn: expiresIn ?? this.expiresIn,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
    );
  }

  TokenResponse$Response copyWithWrapped({
    Wrapped<String>? accessToken,
    Wrapped<int>? expiresIn,
    Wrapped<String>? refreshToken,
    Wrapped<String>? tokenType,
  }) {
    return TokenResponse$Response(
      accessToken: (accessToken != null ? accessToken.value : this.accessToken),
      expiresIn: (expiresIn != null ? expiresIn.value : this.expiresIn),
      refreshToken: (refreshToken != null
          ? refreshToken.value
          : this.refreshToken),
      tokenType: (tokenType != null ? tokenType.value : this.tokenType),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Code$RequestBody {
  const Code$RequestBody({
    required this.clientFriendlyName,
    required this.clientId,
    required this.email,
  });

  factory Code$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$Code$RequestBodyFromJson(json);

  static const toJsonFactory = _$Code$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$Code$RequestBodyToJson(this);

  @JsonKey(name: 'clientFriendlyName')
  final String clientFriendlyName;
  @JsonKey(name: 'clientId')
  final String clientId;
  @JsonKey(name: 'email')
  final String email;
  static const fromJsonFactory = _$Code$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Code$RequestBody &&
            (identical(other.clientFriendlyName, clientFriendlyName) ||
                const DeepCollectionEquality().equals(
                  other.clientFriendlyName,
                  clientFriendlyName,
                )) &&
            (identical(other.clientId, clientId) ||
                const DeepCollectionEquality().equals(
                  other.clientId,
                  clientId,
                )) &&
            (identical(other.email, email) ||
                const DeepCollectionEquality().equals(other.email, email)));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(clientFriendlyName) ^
      const DeepCollectionEquality().hash(clientId) ^
      const DeepCollectionEquality().hash(email) ^
      runtimeType.hashCode;
}

extension $Code$RequestBodyExtension on Code$RequestBody {
  Code$RequestBody copyWith({
    String? clientFriendlyName,
    String? clientId,
    String? email,
  }) {
    return Code$RequestBody(
      clientFriendlyName: clientFriendlyName ?? this.clientFriendlyName,
      clientId: clientId ?? this.clientId,
      email: email ?? this.email,
    );
  }

  Code$RequestBody copyWithWrapped({
    Wrapped<String>? clientFriendlyName,
    Wrapped<String>? clientId,
    Wrapped<String>? email,
  }) {
    return Code$RequestBody(
      clientFriendlyName: (clientFriendlyName != null
          ? clientFriendlyName.value
          : this.clientFriendlyName),
      clientId: (clientId != null ? clientId.value : this.clientId),
      email: (email != null ? email.value : this.email),
    );
  }
}

@JsonSerializable(explicitToJson: true)
class Validate$RequestBody {
  const Validate$RequestBody({required this.code, required this.reference});

  factory Validate$RequestBody.fromJson(Map<String, dynamic> json) =>
      _$Validate$RequestBodyFromJson(json);

  static const toJsonFactory = _$Validate$RequestBodyToJson;
  Map<String, dynamic> toJson() => _$Validate$RequestBodyToJson(this);

  @JsonKey(name: 'code')
  final String code;
  @JsonKey(name: 'reference')
  final String reference;
  static const fromJsonFactory = _$Validate$RequestBodyFromJson;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Validate$RequestBody &&
            (identical(other.code, code) ||
                const DeepCollectionEquality().equals(other.code, code)) &&
            (identical(other.reference, reference) ||
                const DeepCollectionEquality().equals(
                  other.reference,
                  reference,
                )));
  }

  @override
  String toString() => jsonEncode(this);

  @override
  int get hashCode =>
      const DeepCollectionEquality().hash(code) ^
      const DeepCollectionEquality().hash(reference) ^
      runtimeType.hashCode;
}

extension $Validate$RequestBodyExtension on Validate$RequestBody {
  Validate$RequestBody copyWith({String? code, String? reference}) {
    return Validate$RequestBody(
      code: code ?? this.code,
      reference: reference ?? this.reference,
    );
  }

  Validate$RequestBody copyWithWrapped({
    Wrapped<String>? code,
    Wrapped<String>? reference,
  }) {
    return Validate$RequestBody(
      code: (code != null ? code.value : this.code),
      reference: (reference != null ? reference.value : this.reference),
    );
  }
}

String? devicePathTypeNullableToJson(enums.DevicePathType? devicePathType) {
  return devicePathType?.value;
}

String? devicePathTypeToJson(enums.DevicePathType devicePathType) {
  return devicePathType.value;
}

enums.DevicePathType devicePathTypeFromJson(
  Object? devicePathType, [
  enums.DevicePathType? defaultValue,
]) {
  return enums.DevicePathType.values.firstWhereOrNull(
        (e) => e.value == devicePathType,
      ) ??
      defaultValue ??
      enums.DevicePathType.swaggerGeneratedUnknown;
}

enums.DevicePathType? devicePathTypeNullableFromJson(
  Object? devicePathType, [
  enums.DevicePathType? defaultValue,
]) {
  if (devicePathType == null) {
    return null;
  }
  return enums.DevicePathType.values.firstWhereOrNull(
        (e) => e.value == devicePathType,
      ) ??
      defaultValue;
}

String devicePathTypeExplodedListToJson(
  List<enums.DevicePathType>? devicePathType,
) {
  return devicePathType?.map((e) => e.value!).join(',') ?? '';
}

List<String> devicePathTypeListToJson(
  List<enums.DevicePathType>? devicePathType,
) {
  if (devicePathType == null) {
    return [];
  }

  return devicePathType.map((e) => e.value!).toList();
}

List<enums.DevicePathType> devicePathTypeListFromJson(
  List? devicePathType, [
  List<enums.DevicePathType>? defaultValue,
]) {
  if (devicePathType == null) {
    return defaultValue ?? [];
  }

  return devicePathType
      .map((e) => devicePathTypeFromJson(e.toString()))
      .toList();
}

List<enums.DevicePathType>? devicePathTypeNullableListFromJson(
  List? devicePathType, [
  List<enums.DevicePathType>? defaultValue,
]) {
  if (devicePathType == null) {
    return defaultValue;
  }

  return devicePathType
      .map((e) => devicePathTypeFromJson(e.toString()))
      .toList();
}

String? clientV1AuthInitiatePostTypeNullableToJson(
  enums.ClientV1AuthInitiatePostType? clientV1AuthInitiatePostType,
) {
  return clientV1AuthInitiatePostType?.value;
}

String? clientV1AuthInitiatePostTypeToJson(
  enums.ClientV1AuthInitiatePostType clientV1AuthInitiatePostType,
) {
  return clientV1AuthInitiatePostType.value;
}

enums.ClientV1AuthInitiatePostType clientV1AuthInitiatePostTypeFromJson(
  Object? clientV1AuthInitiatePostType, [
  enums.ClientV1AuthInitiatePostType? defaultValue,
]) {
  return enums.ClientV1AuthInitiatePostType.values.firstWhereOrNull(
        (e) => e.value == clientV1AuthInitiatePostType,
      ) ??
      defaultValue ??
      enums.ClientV1AuthInitiatePostType.swaggerGeneratedUnknown;
}

enums.ClientV1AuthInitiatePostType?
clientV1AuthInitiatePostTypeNullableFromJson(
  Object? clientV1AuthInitiatePostType, [
  enums.ClientV1AuthInitiatePostType? defaultValue,
]) {
  if (clientV1AuthInitiatePostType == null) {
    return null;
  }
  return enums.ClientV1AuthInitiatePostType.values.firstWhereOrNull(
        (e) => e.value == clientV1AuthInitiatePostType,
      ) ??
      defaultValue;
}

String clientV1AuthInitiatePostTypeExplodedListToJson(
  List<enums.ClientV1AuthInitiatePostType>? clientV1AuthInitiatePostType,
) {
  return clientV1AuthInitiatePostType?.map((e) => e.value!).join(',') ?? '';
}

List<String> clientV1AuthInitiatePostTypeListToJson(
  List<enums.ClientV1AuthInitiatePostType>? clientV1AuthInitiatePostType,
) {
  if (clientV1AuthInitiatePostType == null) {
    return [];
  }

  return clientV1AuthInitiatePostType.map((e) => e.value!).toList();
}

List<enums.ClientV1AuthInitiatePostType>
clientV1AuthInitiatePostTypeListFromJson(
  List? clientV1AuthInitiatePostType, [
  List<enums.ClientV1AuthInitiatePostType>? defaultValue,
]) {
  if (clientV1AuthInitiatePostType == null) {
    return defaultValue ?? [];
  }

  return clientV1AuthInitiatePostType
      .map((e) => clientV1AuthInitiatePostTypeFromJson(e.toString()))
      .toList();
}

List<enums.ClientV1AuthInitiatePostType>?
clientV1AuthInitiatePostTypeNullableListFromJson(
  List? clientV1AuthInitiatePostType, [
  List<enums.ClientV1AuthInitiatePostType>? defaultValue,
]) {
  if (clientV1AuthInitiatePostType == null) {
    return defaultValue;
  }

  return clientV1AuthInitiatePostType
      .map((e) => clientV1AuthInitiatePostTypeFromJson(e.toString()))
      .toList();
}

String? clientV1AuthTokenPostTypeNullableToJson(
  enums.ClientV1AuthTokenPostType? clientV1AuthTokenPostType,
) {
  return clientV1AuthTokenPostType?.value;
}

String? clientV1AuthTokenPostTypeToJson(
  enums.ClientV1AuthTokenPostType clientV1AuthTokenPostType,
) {
  return clientV1AuthTokenPostType.value;
}

enums.ClientV1AuthTokenPostType clientV1AuthTokenPostTypeFromJson(
  Object? clientV1AuthTokenPostType, [
  enums.ClientV1AuthTokenPostType? defaultValue,
]) {
  return enums.ClientV1AuthTokenPostType.values.firstWhereOrNull(
        (e) => e.value == clientV1AuthTokenPostType,
      ) ??
      defaultValue ??
      enums.ClientV1AuthTokenPostType.swaggerGeneratedUnknown;
}

enums.ClientV1AuthTokenPostType? clientV1AuthTokenPostTypeNullableFromJson(
  Object? clientV1AuthTokenPostType, [
  enums.ClientV1AuthTokenPostType? defaultValue,
]) {
  if (clientV1AuthTokenPostType == null) {
    return null;
  }
  return enums.ClientV1AuthTokenPostType.values.firstWhereOrNull(
        (e) => e.value == clientV1AuthTokenPostType,
      ) ??
      defaultValue;
}

String clientV1AuthTokenPostTypeExplodedListToJson(
  List<enums.ClientV1AuthTokenPostType>? clientV1AuthTokenPostType,
) {
  return clientV1AuthTokenPostType?.map((e) => e.value!).join(',') ?? '';
}

List<String> clientV1AuthTokenPostTypeListToJson(
  List<enums.ClientV1AuthTokenPostType>? clientV1AuthTokenPostType,
) {
  if (clientV1AuthTokenPostType == null) {
    return [];
  }

  return clientV1AuthTokenPostType.map((e) => e.value!).toList();
}

List<enums.ClientV1AuthTokenPostType> clientV1AuthTokenPostTypeListFromJson(
  List? clientV1AuthTokenPostType, [
  List<enums.ClientV1AuthTokenPostType>? defaultValue,
]) {
  if (clientV1AuthTokenPostType == null) {
    return defaultValue ?? [];
  }

  return clientV1AuthTokenPostType
      .map((e) => clientV1AuthTokenPostTypeFromJson(e.toString()))
      .toList();
}

List<enums.ClientV1AuthTokenPostType>?
clientV1AuthTokenPostTypeNullableListFromJson(
  List? clientV1AuthTokenPostType, [
  List<enums.ClientV1AuthTokenPostType>? defaultValue,
]) {
  if (clientV1AuthTokenPostType == null) {
    return defaultValue;
  }

  return clientV1AuthTokenPostType
      .map((e) => clientV1AuthTokenPostTypeFromJson(e.toString()))
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
