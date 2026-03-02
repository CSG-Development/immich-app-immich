// coverage:ignore-file
// ignore_for_file: type=lint

import 'package:json_annotation/json_annotation.dart';
import 'package:collection/collection.dart';

enum AboutOsState {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('normal')
  normal('normal'),
  @JsonValue('recovery')
  recovery('recovery'),
  @JsonValue('update')
  update('update'),
  @JsonValue('provisioning')
  provisioning('provisioning'),
  @JsonValue('unknown')
  unknown('unknown'),
  @JsonValue('reset')
  reset('reset');

  final String? value;

  const AboutOsState(this.value);
}

enum AboutNetworkType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('wired')
  wired('wired'),
  @JsonValue('wireless')
  wireless('wireless');

  final String? value;

  const AboutNetworkType(this.value);
}

enum AuthResponseType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('Bearer')
  bearer('Bearer');

  final String? value;

  const AuthResponseType(this.value);
}

enum StatusState {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('starting')
  starting('starting'),
  @JsonValue('ready')
  ready('ready'),
  @JsonValue('unknown')
  unknown('unknown'),
  @JsonValue('error')
  error('error');

  final String? value;

  const StatusState(this.value);
}

enum AuthRefreshPost$RequestBodyGrantType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('refresh_token')
  refreshToken('refresh_token');

  final String? value;

  const AuthRefreshPost$RequestBodyGrantType(this.value);
}
