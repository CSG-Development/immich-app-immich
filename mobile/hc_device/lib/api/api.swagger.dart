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
