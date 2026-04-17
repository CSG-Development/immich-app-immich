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

enum ButtonStatusType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('idle')
  idle('idle'),
  @JsonValue('waiting')
  waiting('waiting'),
  @JsonValue('locked')
  locked('locked');

  final String? value;

  const ButtonStatusType(this.value);
}

enum DiskHealthStatus {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('healthy')
  healthy('healthy'),
  @JsonValue('warning')
  warning('warning'),
  @JsonValue('critical')
  critical('critical'),
  @JsonValue('unavailable')
  unavailable('unavailable');

  final String? value;

  const DiskHealthStatus(this.value);
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

enum SetupState {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('not_done')
  notDone('not_done'),
  @JsonValue('in_progress')
  inProgress('in_progress'),
  @JsonValue('done')
  done('done'),
  @JsonValue('error')
  error('error');

  final String? value;

  const SetupState(this.value);
}

enum State {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('not_started')
  notStarted('not_started'),
  @JsonValue('starting')
  starting('starting'),
  @JsonValue('ready')
  ready('ready'),
  @JsonValue('error')
  error('error');

  final String? value;

  const State(this.value);
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

enum WifiAuthentication {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('Open')
  open('Open'),
  @JsonValue('WEP')
  wep('WEP'),
  @JsonValue('WPA-Personal')
  wpaPersonal('WPA-Personal'),
  @JsonValue('WPA2-Personal')
  wpa2Personal('WPA2-Personal'),
  @JsonValue('WPA3-Personal')
  wpa3Personal('WPA3-Personal'),
  @JsonValue('WPA-Enterprise')
  wpaEnterprise('WPA-Enterprise'),
  @JsonValue('WPA2-Enterprise')
  wpa2Enterprise('WPA2-Enterprise'),
  @JsonValue('WPA3-Enterprise')
  wpa3Enterprise('WPA3-Enterprise'),
  @JsonValue('WPA')
  wpa('WPA'),
  @JsonValue('WPA2')
  wpa2('WPA2'),
  @JsonValue('WPA3')
  wpa3('WPA3'),
  @JsonValue('Unknown')
  unknown('Unknown');

  final String? value;

  const WifiAuthentication(this.value);
}

enum WifiNetworkState {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('ASSOCIATED')
  associated('ASSOCIATED'),
  @JsonValue('ASSOCIATING')
  associating('ASSOCIATING'),
  @JsonValue('AUTHENTICATING')
  authenticating('AUTHENTICATING'),
  @JsonValue('COMPLETED')
  completed('COMPLETED'),
  @JsonValue('DISCONNECTED')
  disconnected('DISCONNECTED'),
  @JsonValue('FOUR_WAY_HANDSHAKE')
  fourWayHandshake('FOUR_WAY_HANDSHAKE'),
  @JsonValue('GROUP_HANDSHAKE')
  groupHandshake('GROUP_HANDSHAKE'),
  @JsonValue('INACTIVE')
  inactive('INACTIVE'),
  @JsonValue('INTERFACE_DISABLED')
  interfaceDisabled('INTERFACE_DISABLED'),
  @JsonValue('SCANNING')
  scanning('SCANNING'),
  @JsonValue('UNINITIALIZED')
  uninitialized('UNINITIALIZED'),
  @JsonValue('UNKNOWN')
  unknown('UNKNOWN');

  final String? value;

  const WifiNetworkState(this.value);
}

enum AuthRefreshPost$RequestBodyGrantType {
  @JsonValue(null)
  swaggerGeneratedUnknown(null),

  @JsonValue('refresh_token')
  refreshToken('refresh_token');

  final String? value;

  const AuthRefreshPost$RequestBodyGrantType(this.value);
}
