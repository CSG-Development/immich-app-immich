// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api.swagger.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

About _$AboutFromJson(Map<String, dynamic> json) => About(
  certificateCommonName: json['certificate_common_name'] as String,
  date: DateTime.parse(json['date'] as String),
  defaultMacAddr: json['default_mac_addr'] as String,
  hardwareInfo: AboutHardware.fromJson(
    json['hardware_info'] as Map<String, dynamic>,
  ),
  hostname: json['hostname'] as String,
  installId: json['install_id'] as String,
  modelName: json['model_name'] as String,
  modelNumber: json['model_number'] as String,
  networkInterfaces:
      (json['network_interfaces'] as List<dynamic>?)
          ?.map((e) => AboutNetwork.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  osState: aboutOsStateFromJson(json['os_state']),
  productId: json['product_id'] as String,
  serialNumber: json['serial_number'] as String,
  version: json['version'] as String,
);

Map<String, dynamic> _$AboutToJson(About instance) => <String, dynamic>{
  'certificate_common_name': instance.certificateCommonName,
  'date': instance.date.toIso8601String(),
  'default_mac_addr': instance.defaultMacAddr,
  'hardware_info': instance.hardwareInfo.toJson(),
  'hostname': instance.hostname,
  'install_id': instance.installId,
  'model_name': instance.modelName,
  'model_number': instance.modelNumber,
  'network_interfaces': instance.networkInterfaces
      .map((e) => e.toJson())
      .toList(),
  'os_state': aboutOsStateToJson(instance.osState),
  'product_id': instance.productId,
  'serial_number': instance.serialNumber,
  'version': instance.version,
};

AboutHardware _$AboutHardwareFromJson(Map<String, dynamic> json) =>
    AboutHardware(
      memory: (json['memory'] as num).toDouble(),
      processorCount: (json['processor_count'] as num).toInt(),
      processorType: json['processor_type'] as String,
    );

Map<String, dynamic> _$AboutHardwareToJson(AboutHardware instance) =>
    <String, dynamic>{
      'memory': instance.memory,
      'processor_count': instance.processorCount,
      'processor_type': instance.processorType,
    };

AboutIPv4Info _$AboutIPv4InfoFromJson(Map<String, dynamic> json) =>
    AboutIPv4Info(
      gateway: json['gateway'] as String,
      ipv4: json['ipv4'] as String,
      netmask: json['netmask'] as String,
    );

Map<String, dynamic> _$AboutIPv4InfoToJson(AboutIPv4Info instance) =>
    <String, dynamic>{
      'gateway': instance.gateway,
      'ipv4': instance.ipv4,
      'netmask': instance.netmask,
    };

AboutNetwork _$AboutNetworkFromJson(Map<String, dynamic> json) => AboutNetwork(
  ipv4Info: json['ipv4_info'] == null
      ? null
      : AboutIPv4Info.fromJson(json['ipv4_info'] as Map<String, dynamic>),
  link: json['link'] as String?,
  macAddress: json['mac_address'] as String,
  name: json['name'] as String,
  type: aboutNetworkTypeFromJson(json['type']),
);

Map<String, dynamic> _$AboutNetworkToJson(AboutNetwork instance) =>
    <String, dynamic>{
      'ipv4_info': instance.ipv4Info?.toJson(),
      'link': instance.link,
      'mac_address': instance.macAddress,
      'name': instance.name,
      'type': aboutNetworkTypeToJson(instance.type),
    };

AppStatus _$AppStatusFromJson(Map<String, dynamic> json) =>
    AppStatus(files: json['files'] as String, photos: json['photos'] as String);

Map<String, dynamic> _$AppStatusToJson(AppStatus instance) => <String, dynamic>{
  'files': instance.files,
  'photos': instance.photos,
};

AuthResponse _$AuthResponseFromJson(Map<String, dynamic> json) => AuthResponse(
  accessToken: json['access_token'] as String,
  expiresIn: (json['expires_in'] as num).toInt(),
  refreshToken: json['refresh_token'] as String,
  type: authResponseTypeFromJson(json['type']),
);

Map<String, dynamic> _$AuthResponseToJson(AuthResponse instance) =>
    <String, dynamic>{
      'access_token': instance.accessToken,
      'expires_in': instance.expiresIn,
      'refresh_token': instance.refreshToken,
      'type': authResponseTypeToJson(instance.type),
    };

Error _$ErrorFromJson(Map<String, dynamic> json) => Error(
  name: json['name'] as String,
  stacktrace: json['stacktrace'] as String,
  reason: json['reason'] as String?,
);

Map<String, dynamic> _$ErrorToJson(Error instance) => <String, dynamic>{
  'name': instance.name,
  'stacktrace': instance.stacktrace,
  'reason': instance.reason,
};

Oobe _$OobeFromJson(Map<String, dynamic> json) =>
    Oobe(done: json['done'] as bool);

Map<String, dynamic> _$OobeToJson(Oobe instance) => <String, dynamic>{
  'done': instance.done,
};

Status _$StatusFromJson(Map<String, dynamic> json) => Status(
  oobe: Oobe.fromJson(json['OOBE'] as Map<String, dynamic>),
  apps: AppStatus.fromJson(json['apps'] as Map<String, dynamic>),
  state: statusStateFromJson(json['state']),
);

Map<String, dynamic> _$StatusToJson(Status instance) => <String, dynamic>{
  'OOBE': instance.oobe.toJson(),
  'apps': instance.apps.toJson(),
  'state': statusStateToJson(instance.state),
};

AuthLoginPost$RequestBody _$AuthLoginPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => AuthLoginPost$RequestBody(
  email: json['email'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$AuthLoginPost$RequestBodyToJson(
  AuthLoginPost$RequestBody instance,
) => <String, dynamic>{'email': instance.email, 'password': instance.password};

AuthLogoutPost$RequestBody _$AuthLogoutPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => AuthLogoutPost$RequestBody(refreshToken: json['refresh_token'] as String);

Map<String, dynamic> _$AuthLogoutPost$RequestBodyToJson(
  AuthLogoutPost$RequestBody instance,
) => <String, dynamic>{'refresh_token': instance.refreshToken};

AuthRefreshPost$RequestBody _$AuthRefreshPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => AuthRefreshPost$RequestBody(
  grantType: authRefreshPost$RequestBodyGrantTypeFromJson(json['grant_type']),
  refreshToken: json['refresh_token'] as String,
);

Map<String, dynamic> _$AuthRefreshPost$RequestBodyToJson(
  AuthRefreshPost$RequestBody instance,
) => <String, dynamic>{
  'grant_type': authRefreshPost$RequestBodyGrantTypeToJson(instance.grantType),
  'refresh_token': instance.refreshToken,
};
