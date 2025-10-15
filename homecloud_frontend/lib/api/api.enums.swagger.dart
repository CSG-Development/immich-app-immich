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

enum DuplexType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('full')
  full('full'),
  @JsonValue('half')
  half('half');

  final String? value;

  const DuplexType(this.value);
}

enum LinkStatus {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('up')
  up('up'),
  @JsonValue('down')
  down('down');

  final String? value;

  const LinkStatus(this.value);
}

enum NetworkInterfaceType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('wired')
  wired('wired'),
  @JsonValue('wireless')
  wireless('wireless');

  final String? value;

  const NetworkInterfaceType(this.value);
}

enum PowerOffType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('shutdown')
  shutdown('shutdown'),
  @JsonValue('reboot')
  reboot('reboot');

  final String? value;

  const PowerOffType(this.value);
}

enum ResetType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('reset_settings')
  resetSettings('reset_settings'),
  @JsonValue('reset_device')
  resetDevice('reset_device'),
  @JsonValue('reset_provisioning')
  resetProvisioning('reset_provisioning');

  final String? value;

  const ResetType(this.value);
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

enum UpdateType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('online')
  online('online'),
  @JsonValue('offline')
  offline('offline'),
  @JsonValue('all')
  all('all'),
  @JsonValue('unknown')
  unknown('unknown');

  final String? value;

  const UpdateType(this.value);
}

enum AuthRefreshPost$RequestBodyGrantType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('refresh_token')
  refreshToken('refresh_token');

  final String? value;

  const AuthRefreshPost$RequestBodyGrantType(this.value);
}
