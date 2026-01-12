// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'remote_access.swagger.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Device _$DeviceFromJson(Map<String, dynamic> json) => Device(
  certificateCommonName: json['certificateCommonName'] as String,
  friendlyName: json['friendlyName'] as String,
  hostname: json['hostname'] as String,
  seagateDeviceID: json['seagateDeviceID'] as String,
);

Map<String, dynamic> _$DeviceToJson(Device instance) => <String, dynamic>{
  'certificateCommonName': instance.certificateCommonName,
  'friendlyName': instance.friendlyName,
  'hostname': instance.hostname,
  'seagateDeviceID': instance.seagateDeviceID,
};

DevicePaths _$DevicePathsFromJson(Map<String, dynamic> json) => DevicePaths(
  paths:
      (json['paths'] as List<dynamic>?)
          ?.map((e) => DevicePath.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  seagateDeviceID: json['seagateDeviceID'] as String,
);

Map<String, dynamic> _$DevicePathsToJson(DevicePaths instance) =>
    <String, dynamic>{
      'paths': instance.paths.map((e) => e.toJson()).toList(),
      'seagateDeviceID': instance.seagateDeviceID,
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

DevicePath _$DevicePathFromJson(Map<String, dynamic> json) => DevicePath(
  address: json['address'] as String,
  port: (json['port'] as num?)?.toInt(),
  type: devicePathTypeFromJson(json['type']),
);

Map<String, dynamic> _$DevicePathToJson(DevicePath instance) =>
    <String, dynamic>{
      'address': instance.address,
      'port': instance.port,
      'type': devicePathTypeToJson(instance.type),
    };

InitiateResponse$Response _$InitiateResponse$ResponseFromJson(
  Map<String, dynamic> json,
) => InitiateResponse$Response(reference: json['reference'] as String);

Map<String, dynamic> _$InitiateResponse$ResponseToJson(
  InitiateResponse$Response instance,
) => <String, dynamic>{'reference': instance.reference};

TokenResponse$Response _$TokenResponse$ResponseFromJson(
  Map<String, dynamic> json,
) => TokenResponse$Response(
  accessToken: json['accessToken'] as String,
  expiresIn: (json['expiresIn'] as num).toInt(),
  refreshToken: json['refreshToken'] as String,
  tokenType: json['tokenType'] as String,
);

Map<String, dynamic> _$TokenResponse$ResponseToJson(
  TokenResponse$Response instance,
) => <String, dynamic>{
  'accessToken': instance.accessToken,
  'expiresIn': instance.expiresIn,
  'refreshToken': instance.refreshToken,
  'tokenType': instance.tokenType,
};

Code$RequestBody _$Code$RequestBodyFromJson(Map<String, dynamic> json) =>
    Code$RequestBody(
      clientFriendlyName: json['clientFriendlyName'] as String,
      clientId: json['clientId'] as String,
      email: json['email'] as String,
    );

Map<String, dynamic> _$Code$RequestBodyToJson(Code$RequestBody instance) =>
    <String, dynamic>{
      'clientFriendlyName': instance.clientFriendlyName,
      'clientId': instance.clientId,
      'email': instance.email,
    };

Validate$RequestBody _$Validate$RequestBodyFromJson(
  Map<String, dynamic> json,
) => Validate$RequestBody(
  code: json['code'] as String,
  clientId: json['clientId'] as String,
  reference: json['reference'] as String,
);

Map<String, dynamic> _$Validate$RequestBodyToJson(
  Validate$RequestBody instance,
) => <String, dynamic>{
  'code': instance.code,
  'clientId': instance.clientId,
  'reference': instance.reference,
};
