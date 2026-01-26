// coverage:ignore-file
// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';
import 'package:collection/collection.dart';

enum DevicePathType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('local')
  local('local'),
  @JsonValue('public')
  public('public'),
  @JsonValue('remote')
  remote('remote');

  final String? value;

  const DevicePathType(this.value);
}

enum ClientV1AuthInitiatePostType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('email')
  email('email');

  final String? value;

  const ClientV1AuthInitiatePostType(this.value);
}

enum ClientV1AuthTokenPostType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('email')
  email('email');

  final String? value;

  const ClientV1AuthTokenPostType(this.value);
}
