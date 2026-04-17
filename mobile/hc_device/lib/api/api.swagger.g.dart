// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api.swagger.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

About _$AboutFromJson(Map<String, dynamic> json) => About(
  boardName: json['board_name'] as String? ?? '',
  boardVersion: json['board_version'] as String? ?? '',
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
  'board_name': instance.boardName,
  'board_version': instance.boardVersion,
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

AdvancedConfig _$AdvancedConfigFromJson(Map<String, dynamic> json) =>
    AdvancedConfig(
      sshEnabled: json['ssh_enabled'] as bool,
      swaggerUiEnabled: json['swagger_ui_enabled'] as bool,
      updateLabels:
          (json['update_labels'] as List<dynamic>?)
              ?.map((e) => UpdateLabel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$AdvancedConfigToJson(AdvancedConfig instance) =>
    <String, dynamic>{
      'ssh_enabled': instance.sshEnabled,
      'swagger_ui_enabled': instance.swaggerUiEnabled,
      'update_labels': instance.updateLabels.map((e) => e.toJson()).toList(),
    };

AppStatus _$AppStatusFromJson(Map<String, dynamic> json) => AppStatus(
  files: stateFromJson(json['files']),
  photos: stateFromJson(json['photos']),
);

Map<String, dynamic> _$AppStatusToJson(AppStatus instance) => <String, dynamic>{
  'files': stateToJson(instance.files),
  'photos': stateToJson(instance.photos),
};

ApplicationUsage _$ApplicationUsageFromJson(Map<String, dynamic> json) =>
    ApplicationUsage(
      name: json['name'] as String,
      usedBytes: (json['used_bytes'] as num).toInt(),
    );

Map<String, dynamic> _$ApplicationUsageToJson(ApplicationUsage instance) =>
    <String, dynamic>{'name': instance.name, 'used_bytes': instance.usedBytes};

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

AuthorizeRequest _$AuthorizeRequestFromJson(Map<String, dynamic> json) =>
    AuthorizeRequest(
      clientId: json['client_id'] as String,
      codeChallenge: json['code_challenge'] as String,
      codeChallengeMethod: json['code_challenge_method'] as String,
      redirectUri: json['redirect_uri'] as String,
      responseType: json['response_type'] as String,
      scope: json['scope'] as String,
      state: json['state'] as String,
    );

Map<String, dynamic> _$AuthorizeRequestToJson(AuthorizeRequest instance) =>
    <String, dynamic>{
      'client_id': instance.clientId,
      'code_challenge': instance.codeChallenge,
      'code_challenge_method': instance.codeChallengeMethod,
      'redirect_uri': instance.redirectUri,
      'response_type': instance.responseType,
      'scope': instance.scope,
      'state': instance.state,
    };

AuthorizeResponse _$AuthorizeResponseFromJson(Map<String, dynamic> json) =>
    AuthorizeResponse(redirectUri: json['redirect_uri'] as String);

Map<String, dynamic> _$AuthorizeResponseToJson(AuthorizeResponse instance) =>
    <String, dynamic>{'redirect_uri': instance.redirectUri};

ButtonAction _$ButtonActionFromJson(Map<String, dynamic> json) =>
    ButtonAction(code: json['code'] as String);

Map<String, dynamic> _$ButtonActionToJson(ButtonAction instance) =>
    <String, dynamic>{'code': instance.code};

ButtonStatus _$ButtonStatusFromJson(Map<String, dynamic> json) =>
    ButtonStatus(status: buttonStatusTypeFromJson(json['status']));

Map<String, dynamic> _$ButtonStatusToJson(ButtonStatus instance) =>
    <String, dynamic>{'status': buttonStatusTypeToJson(instance.status)};

DeviceConfiguration _$DeviceConfigurationFromJson(Map<String, dynamic> json) =>
    DeviceConfiguration(
      biosPasswordSet: json['bios_password_set'] as bool,
      deviceCertificateSignedBy: json['device_certificate_signed_by'] == null
          ? null
          : DeviceConfigurationCertificate.fromJson(
              json['device_certificate_signed_by'] as Map<String, dynamic>,
            ),
      prodFailureReasons:
          (json['prod_failure_reasons'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      prodReady: json['prod_ready'] as bool,
      provisioningVault: DeviceConfigurationProvisioningVault.fromJson(
        json['provisioning_vault'] as Map<String, dynamic>,
      ),
      psidSet: json['psid_set'] as bool,
      secureBootEnabled: json['secure_boot_enabled'] as bool,
    );

Map<String, dynamic> _$DeviceConfigurationToJson(
  DeviceConfiguration instance,
) => <String, dynamic>{
  'bios_password_set': instance.biosPasswordSet,
  'device_certificate_signed_by': instance.deviceCertificateSignedBy?.toJson(),
  'prod_failure_reasons': instance.prodFailureReasons,
  'prod_ready': instance.prodReady,
  'provisioning_vault': instance.provisioningVault.toJson(),
  'psid_set': instance.psidSet,
  'secure_boot_enabled': instance.secureBootEnabled,
};

DeviceConfigurationCertificate _$DeviceConfigurationCertificateFromJson(
  Map<String, dynamic> json,
) => DeviceConfigurationCertificate(
  name: json['name'] as String,
  value: json['value'] as String,
);

Map<String, dynamic> _$DeviceConfigurationCertificateToJson(
  DeviceConfigurationCertificate instance,
) => <String, dynamic>{'name': instance.name, 'value': instance.value};

DeviceConfigurationProvisioningVault
_$DeviceConfigurationProvisioningVaultFromJson(Map<String, dynamic> json) =>
    DeviceConfigurationProvisioningVault(
      ssid: json['SSID'] as String?,
      certificates:
          (json['certificates'] as List<dynamic>?)
              ?.map(
                (e) => DeviceConfigurationCertificate.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList() ??
          [],
      creationDate: DateTime.parse(json['creation_date'] as String),
      signedBy: DeviceConfigurationCertificate.fromJson(
        json['signed_by'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$DeviceConfigurationProvisioningVaultToJson(
  DeviceConfigurationProvisioningVault instance,
) => <String, dynamic>{
  'SSID': instance.ssid,
  'certificates': instance.certificates?.map((e) => e.toJson()).toList(),
  'creation_date': instance.creationDate.toIso8601String(),
  'signed_by': instance.signedBy.toJson(),
};

DiskHealth _$DiskHealthFromJson(Map<String, dynamic> json) => DiskHealth(
  status: diskHealthStatusFromJson(json['status']),
  summary: json['summary'] as String?,
  temperatureCelsius: (json['temperature_celsius'] as num?)?.toInt(),
);

Map<String, dynamic> _$DiskHealthToJson(DiskHealth instance) =>
    <String, dynamic>{
      'status': diskHealthStatusToJson(instance.status),
      'summary': instance.summary,
      'temperature_celsius': instance.temperatureCelsius,
    };

DiskStats _$DiskStatsFromJson(Map<String, dynamic> json) => DiskStats(
  freeBytes: (json['free_bytes'] as num).toInt(),
  totalBytes: (json['total_bytes'] as num).toInt(),
  usagePercent: (json['usage_percent'] as num).toDouble(),
  usedBytes: (json['used_bytes'] as num).toInt(),
);

Map<String, dynamic> _$DiskStatsToJson(DiskStats instance) => <String, dynamic>{
  'free_bytes': instance.freeBytes,
  'total_bytes': instance.totalBytes,
  'usage_percent': instance.usagePercent,
  'used_bytes': instance.usedBytes,
};

EmailChangeRequest _$EmailChangeRequestFromJson(Map<String, dynamic> json) =>
    EmailChangeRequest(
      creationDate: DateTime.parse(json['creation_date'] as String),
      expirationDate: DateTime.parse(json['expiration_date'] as String),
      isExpired: json['is_expired'] as bool,
      newEmail: json['new_email'] as String,
      userId: json['user_id'] as String,
    );

Map<String, dynamic> _$EmailChangeRequestToJson(EmailChangeRequest instance) =>
    <String, dynamic>{
      'creation_date': instance.creationDate.toIso8601String(),
      'expiration_date': instance.expirationDate.toIso8601String(),
      'is_expired': instance.isExpired,
      'new_email': instance.newEmail,
      'user_id': instance.userId,
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

HardwareInfo _$HardwareInfoFromJson(Map<String, dynamic> json) => HardwareInfo(
  autoNegotiation: json['auto_negotiation'] as bool,
  isActive: json['is_active'] as bool,
  isLoopback: json['is_loopback'] as bool,
  macAddress: json['mac_address'] as String,
  maxSpeed: (json['max_speed'] as num).toInt(),
  maxSpeedDuplex: duplexTypeFromJson(json['max_speed_duplex']),
  maximumMtu: (json['maximum_mtu'] as num).toInt(),
  minimumMtu: (json['minimum_mtu'] as num).toInt(),
  model: json['model'] as String,
  mtu: (json['mtu'] as num).toInt(),
  vendor: json['vendor'] as String,
);

Map<String, dynamic> _$HardwareInfoToJson(HardwareInfo instance) =>
    <String, dynamic>{
      'auto_negotiation': instance.autoNegotiation,
      'is_active': instance.isActive,
      'is_loopback': instance.isLoopback,
      'mac_address': instance.macAddress,
      'max_speed': instance.maxSpeed,
      'max_speed_duplex': duplexTypeToJson(instance.maxSpeedDuplex),
      'maximum_mtu': instance.maximumMtu,
      'minimum_mtu': instance.minimumMtu,
      'model': instance.model,
      'mtu': instance.mtu,
      'vendor': instance.vendor,
    };

IPv4Config _$IPv4ConfigFromJson(Map<String, dynamic> json) => IPv4Config(
  gateway: json['gateway'] as String?,
  ipv4: json['ipv4'] as String,
  nameServers:
      (json['name_servers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  netmask: json['netmask'] as String,
);

Map<String, dynamic> _$IPv4ConfigToJson(IPv4Config instance) =>
    <String, dynamic>{
      'gateway': instance.gateway,
      'ipv4': instance.ipv4,
      'name_servers': instance.nameServers,
      'netmask': instance.netmask,
    };

IPv4Info _$IPv4InfoFromJson(Map<String, dynamic> json) => IPv4Info(
  broadcast: json['broadcast'] as String,
  dhcp: json['dhcp'] as bool,
  gateway: json['gateway'] as String,
  ipv4: json['ipv4'] as String,
  nameServers:
      (json['name_servers'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  netmask: json['netmask'] as String,
);

Map<String, dynamic> _$IPv4InfoToJson(IPv4Info instance) => <String, dynamic>{
  'broadcast': instance.broadcast,
  'dhcp': instance.dhcp,
  'gateway': instance.gateway,
  'ipv4': instance.ipv4,
  'name_servers': instance.nameServers,
  'netmask': instance.netmask,
};

InterfaceConfig _$InterfaceConfigFromJson(Map<String, dynamic> json) =>
    InterfaceConfig(
      dhcp: json['dhcp'] as bool,
      ipv4Config: json['ipv4_config'] == null
          ? null
          : IPv4Config.fromJson(json['ipv4_config'] as Map<String, dynamic>),
      mtu: (json['mtu'] as num?)?.toInt(),
    );

Map<String, dynamic> _$InterfaceConfigToJson(InterfaceConfig instance) =>
    <String, dynamic>{
      'dhcp': instance.dhcp,
      'ipv4_config': instance.ipv4Config?.toJson(),
      'mtu': instance.mtu,
    };

Invite _$InviteFromJson(Map<String, dynamic> json) => Invite(
  creationDate: DateTime.parse(json['creation_date'] as String),
  email: json['email'] as String,
  expirationDate: DateTime.parse(json['expiration_date'] as String),
  isAdmin: json['is_admin'] as bool,
  isExpired: json['is_expired'] as bool,
);

Map<String, dynamic> _$InviteToJson(Invite instance) => <String, dynamic>{
  'creation_date': instance.creationDate.toIso8601String(),
  'email': instance.email,
  'expiration_date': instance.expirationDate.toIso8601String(),
  'is_admin': instance.isAdmin,
  'is_expired': instance.isExpired,
};

JwksResponse _$JwksResponseFromJson(Map<String, dynamic> json) => JwksResponse(
  keys:
      (json['keys'] as List<dynamic>?)?.map((e) => e as Object).toList() ?? [],
);

Map<String, dynamic> _$JwksResponseToJson(JwksResponse instance) =>
    <String, dynamic>{'keys': instance.keys};

LinkInfo _$LinkInfoFromJson(Map<String, dynamic> json) => LinkInfo(
  duplex: duplexTypeFromJson(json['duplex']),
  link: linkStatusFromJson(json['link']),
  speed: (json['speed'] as num).toInt(),
);

Map<String, dynamic> _$LinkInfoToJson(LinkInfo instance) => <String, dynamic>{
  'duplex': duplexTypeToJson(instance.duplex),
  'link': linkStatusToJson(instance.link),
  'speed': instance.speed,
};

NTPConfig _$NTPConfigFromJson(Map<String, dynamic> json) => NTPConfig(
  enabled: json['enabled'] as bool,
  servers:
      (json['servers'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      [],
  synchronized: json['synchronized'] as bool,
);

Map<String, dynamic> _$NTPConfigToJson(NTPConfig instance) => <String, dynamic>{
  'enabled': instance.enabled,
  'servers': instance.servers,
  'synchronized': instance.synchronized,
};

NetworkInterface _$NetworkInterfaceFromJson(Map<String, dynamic> json) =>
    NetworkInterface(
      hardwareInfo: HardwareInfo.fromJson(
        json['hardware_info'] as Map<String, dynamic>,
      ),
      ipv4Info: json['ipv4_info'] == null
          ? null
          : IPv4Info.fromJson(json['ipv4_info'] as Map<String, dynamic>),
      linkInfo: json['link_info'] == null
          ? null
          : LinkInfo.fromJson(json['link_info'] as Map<String, dynamic>),
      name: json['name'] as String,
      type: networkInterfaceTypeFromJson(json['type']),
      wirelessInfo: json['wireless_info'] == null
          ? null
          : WifiNetwork.fromJson(json['wireless_info'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$NetworkInterfaceToJson(NetworkInterface instance) =>
    <String, dynamic>{
      'hardware_info': instance.hardwareInfo.toJson(),
      'ipv4_info': instance.ipv4Info?.toJson(),
      'link_info': instance.linkInfo?.toJson(),
      'name': instance.name,
      'type': networkInterfaceTypeToJson(instance.type),
      'wireless_info': instance.wirelessInfo?.toJson(),
    };

Oobe _$OobeFromJson(Map<String, dynamic> json) =>
    Oobe(done: json['done'] as bool);

Map<String, dynamic> _$OobeToJson(Oobe instance) => <String, dynamic>{
  'done': instance.done,
};

OpenIDConfigurationResponse _$OpenIDConfigurationResponseFromJson(
  Map<String, dynamic> json,
) => OpenIDConfigurationResponse(
  authorizationEndpoint: json['authorization_endpoint'] as String,
  idTokenSigningAlgValuesSupported:
      (json['id_token_signing_alg_values_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  issuer: json['issuer'] as String,
  jwksUri: json['jwks_uri'] as String,
  responseTypesSupported:
      (json['response_types_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  subjectTypesSupported:
      (json['subject_types_supported'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      [],
  tokenEndpoint: json['token_endpoint'] as String,
);

Map<String, dynamic> _$OpenIDConfigurationResponseToJson(
  OpenIDConfigurationResponse instance,
) => <String, dynamic>{
  'authorization_endpoint': instance.authorizationEndpoint,
  'id_token_signing_alg_values_supported':
      instance.idTokenSigningAlgValuesSupported,
  'issuer': instance.issuer,
  'jwks_uri': instance.jwksUri,
  'response_types_supported': instance.responseTypesSupported,
  'subject_types_supported': instance.subjectTypesSupported,
  'token_endpoint': instance.tokenEndpoint,
};

SMTPConfig _$SMTPConfigFromJson(Map<String, dynamic> json) => SMTPConfig(
  password: json['password'] as String,
  port: (json['port'] as num).toInt(),
  server: json['server'] as String,
  tls: json['tls'] as bool,
  user: json['user'] as String,
);

Map<String, dynamic> _$SMTPConfigToJson(SMTPConfig instance) =>
    <String, dynamic>{
      'password': instance.password,
      'port': instance.port,
      'server': instance.server,
      'tls': instance.tls,
      'user': instance.user,
    };

Status _$StatusFromJson(Map<String, dynamic> json) => Status(
  oobe: Oobe.fromJson(json['OOBE'] as Map<String, dynamic>),
  apps: AppStatus.fromJson(json['apps'] as Map<String, dynamic>),
  setup: setupStateFromJson(json['setup']),
  state: stateFromJson(json['state']),
  systemState: stateFromJson(json['system_state']),
);

Map<String, dynamic> _$StatusToJson(Status instance) => <String, dynamic>{
  'OOBE': instance.oobe.toJson(),
  'apps': instance.apps.toJson(),
  'setup': setupStateToJson(instance.setup),
  'state': stateToJson(instance.state),
  'system_state': stateToJson(instance.systemState),
};

StorageStats _$StorageStatsFromJson(Map<String, dynamic> json) => StorageStats(
  applications:
      (json['applications'] as List<dynamic>?)
          ?.map((e) => ApplicationUsage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  disk: DiskStats.fromJson(json['disk'] as Map<String, dynamic>),
  health: DiskHealth.fromJson(json['health'] as Map<String, dynamic>),
  systemBytes: (json['system_bytes'] as num).toInt(),
  users:
      (json['users'] as List<dynamic>?)
          ?.map((e) => UserUsage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$StorageStatsToJson(StorageStats instance) =>
    <String, dynamic>{
      'applications': instance.applications.map((e) => e.toJson()).toList(),
      'disk': instance.disk.toJson(),
      'health': instance.health.toJson(),
      'system_bytes': instance.systemBytes,
      'users': instance.users.map((e) => e.toJson()).toList(),
    };

TimeConfig _$TimeConfigFromJson(Map<String, dynamic> json) => TimeConfig(
  date: DateTime.parse(json['date'] as String),
  ntp: NTPConfig.fromJson(json['ntp'] as Map<String, dynamic>),
  timezone: json['timezone'] as String,
);

Map<String, dynamic> _$TimeConfigToJson(TimeConfig instance) =>
    <String, dynamic>{
      'date': instance.date.toIso8601String(),
      'ntp': instance.ntp.toJson(),
      'timezone': instance.timezone,
    };

Update _$UpdateFromJson(Map<String, dynamic> json) => Update(
  type: updateTypeFromJson(json['type']),
  version: json['version'] as String,
);

Map<String, dynamic> _$UpdateToJson(Update instance) => <String, dynamic>{
  'type': updateTypeToJson(instance.type),
  'version': instance.version,
};

UpdateInfo _$UpdateInfoFromJson(Map<String, dynamic> json) => UpdateInfo(
  currentVersion: json['current_version'] as String,
  targetVersion: json['target_version'] as String,
);

Map<String, dynamic> _$UpdateInfoToJson(UpdateInfo instance) =>
    <String, dynamic>{
      'current_version': instance.currentVersion,
      'target_version': instance.targetVersion,
    };

UpdateLabel _$UpdateLabelFromJson(Map<String, dynamic> json) =>
    UpdateLabel(enabled: json['enabled'] as bool, name: json['name'] as String);

Map<String, dynamic> _$UpdateLabelToJson(UpdateLabel instance) =>
    <String, dynamic>{'enabled': instance.enabled, 'name': instance.name};

UpdateProgress _$UpdateProgressFromJson(Map<String, dynamic> json) =>
    UpdateProgress(progress: (json['progress'] as num).toInt());

Map<String, dynamic> _$UpdateProgressToJson(UpdateProgress instance) =>
    <String, dynamic>{'progress': instance.progress};

User _$UserFromJson(Map<String, dynamic> json) => User(
  email: json['email'] as String,
  error: json['error'] as String,
  isAdmin: json['is_admin'] as bool,
  isOwner: json['is_owner'] as bool,
  name: json['name'] as String,
  userId: json['user_id'] as String,
);

Map<String, dynamic> _$UserToJson(User instance) => <String, dynamic>{
  'email': instance.email,
  'error': instance.error,
  'is_admin': instance.isAdmin,
  'is_owner': instance.isOwner,
  'name': instance.name,
  'user_id': instance.userId,
};

UserStorageStats _$UserStorageStatsFromJson(Map<String, dynamic> json) =>
    UserStorageStats(
      disk: DiskStats.fromJson(json['disk'] as Map<String, dynamic>),
      usagePercent: (json['usage_percent'] as num).toDouble(),
      user: UserUsage.fromJson(json['user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$UserStorageStatsToJson(UserStorageStats instance) =>
    <String, dynamic>{
      'disk': instance.disk.toJson(),
      'usage_percent': instance.usagePercent,
      'user': instance.user.toJson(),
    };

UserUsage _$UserUsageFromJson(Map<String, dynamic> json) => UserUsage(
  applications:
      (json['applications'] as List<dynamic>?)
          ?.map((e) => ApplicationUsage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
  email: json['email'] as String,
  usedBytes: (json['used_bytes'] as num).toInt(),
  userId: json['user_id'] as String,
);

Map<String, dynamic> _$UserUsageToJson(UserUsage instance) => <String, dynamic>{
  'applications': instance.applications.map((e) => e.toJson()).toList(),
  'email': instance.email,
  'used_bytes': instance.usedBytes,
  'user_id': instance.userId,
};

WifiConfig _$WifiConfigFromJson(Map<String, dynamic> json) => WifiConfig(
  hiddenSsid: json['hidden_ssid'] as bool,
  password: json['password'] as String,
  ssid: json['ssid'] as String,
);

Map<String, dynamic> _$WifiConfigToJson(WifiConfig instance) =>
    <String, dynamic>{
      'hidden_ssid': instance.hiddenSsid,
      'password': instance.password,
      'ssid': instance.ssid,
    };

WifiNetwork _$WifiNetworkFromJson(Map<String, dynamic> json) => WifiNetwork(
  bssid: json['bssid'] as String,
  frequency: (json['frequency'] as num).toInt(),
  security: wifiAuthenticationListFromJson(json['security'] as List?),
  signal: (json['signal'] as num).toInt(),
  ssid: json['ssid'] as String,
  state: wifiNetworkStateFromJson(json['state']),
);

Map<String, dynamic> _$WifiNetworkToJson(WifiNetwork instance) =>
    <String, dynamic>{
      'bssid': instance.bssid,
      'frequency': instance.frequency,
      'security': wifiAuthenticationListToJson(instance.security),
      'signal': instance.signal,
      'ssid': instance.ssid,
      'state': wifiNetworkStateToJson(instance.state),
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

OobeOwnerPost$RequestBody _$OobeOwnerPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => OobeOwnerPost$RequestBody(
  code: json['code'] as String,
  email: json['email'] as String,
  name: json['name'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$OobeOwnerPost$RequestBodyToJson(
  OobeOwnerPost$RequestBody instance,
) => <String, dynamic>{
  'code': instance.code,
  'email': instance.email,
  'name': instance.name,
  'password': instance.password,
};

OobeOwnerPut$RequestBody _$OobeOwnerPut$RequestBodyFromJson(
  Map<String, dynamic> json,
) => OobeOwnerPut$RequestBody(
  confirmationCode: json['confirmation_code'] as String,
);

Map<String, dynamic> _$OobeOwnerPut$RequestBodyToJson(
  OobeOwnerPut$RequestBody instance,
) => <String, dynamic>{'confirmation_code': instance.confirmationCode};

OobePowerPost$RequestBody _$OobePowerPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => OobePowerPost$RequestBody(action: powerOffTypeFromJson(json['action']));

Map<String, dynamic> _$OobePowerPost$RequestBodyToJson(
  OobePowerPost$RequestBody instance,
) => <String, dynamic>{'action': powerOffTypeToJson(instance.action)};

PowerPost$RequestBody _$PowerPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => PowerPost$RequestBody(action: powerOffTypeFromJson(json['action']));

Map<String, dynamic> _$PowerPost$RequestBodyToJson(
  PowerPost$RequestBody instance,
) => <String, dynamic>{'action': powerOffTypeToJson(instance.action)};

ResetPost$RequestBody _$ResetPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => ResetPost$RequestBody(
  provisioningPassword: json['provisioning_password'] as String?,
  type: resetTypeFromJson(json['type']),
);

Map<String, dynamic> _$ResetPost$RequestBodyToJson(
  ResetPost$RequestBody instance,
) => <String, dynamic>{
  'provisioning_password': instance.provisioningPassword,
  'type': resetTypeToJson(instance.type),
};

UsersIdPut$RequestBody _$UsersIdPut$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersIdPut$RequestBody(
  isAdmin: json['is_admin'] as bool?,
  name: json['name'] as String?,
  oldPassword: json['old_password'] as String?,
  password: json['password'] as String?,
);

Map<String, dynamic> _$UsersIdPut$RequestBodyToJson(
  UsersIdPut$RequestBody instance,
) => <String, dynamic>{
  'is_admin': instance.isAdmin,
  'name': instance.name,
  'old_password': instance.oldPassword,
  'password': instance.password,
};

UsersChangeEmailIdPost$RequestBody _$UsersChangeEmailIdPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersChangeEmailIdPost$RequestBody(newEmail: json['new_email'] as String);

Map<String, dynamic> _$UsersChangeEmailIdPost$RequestBodyToJson(
  UsersChangeEmailIdPost$RequestBody instance,
) => <String, dynamic>{'new_email': instance.newEmail};

UsersChangeEmailIdPut$RequestBody _$UsersChangeEmailIdPut$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersChangeEmailIdPut$RequestBody(
  confirmationCode: json['confirmation_code'] as String,
);

Map<String, dynamic> _$UsersChangeEmailIdPut$RequestBodyToJson(
  UsersChangeEmailIdPut$RequestBody instance,
) => <String, dynamic>{'confirmation_code': instance.confirmationCode};

UsersInvitesEmailPost$RequestBody _$UsersInvitesEmailPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersInvitesEmailPost$RequestBody(isAdmin: json['is_admin'] as bool);

Map<String, dynamic> _$UsersInvitesEmailPost$RequestBodyToJson(
  UsersInvitesEmailPost$RequestBody instance,
) => <String, dynamic>{'is_admin': instance.isAdmin};

UsersInvitesEmailPut$RequestBody _$UsersInvitesEmailPut$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersInvitesEmailPut$RequestBody(
  confirmationCode: json['confirmation_code'] as String,
  name: json['name'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$UsersInvitesEmailPut$RequestBodyToJson(
  UsersInvitesEmailPut$RequestBody instance,
) => <String, dynamic>{
  'confirmation_code': instance.confirmationCode,
  'name': instance.name,
  'password': instance.password,
};

UsersMePut$RequestBody _$UsersMePut$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersMePut$RequestBody(
  name: json['name'] as String?,
  oldPassword: json['old_password'] as String?,
  password: json['password'] as String?,
);

Map<String, dynamic> _$UsersMePut$RequestBodyToJson(
  UsersMePut$RequestBody instance,
) => <String, dynamic>{
  'name': instance.name,
  'old_password': instance.oldPassword,
  'password': instance.password,
};

UsersResetPasswordEmailPut$RequestBody
_$UsersResetPasswordEmailPut$RequestBodyFromJson(Map<String, dynamic> json) =>
    UsersResetPasswordEmailPut$RequestBody(
      confirmationCode: json['confirmation_code'] as String,
      password: json['password'] as String,
    );

Map<String, dynamic> _$UsersResetPasswordEmailPut$RequestBodyToJson(
  UsersResetPasswordEmailPut$RequestBody instance,
) => <String, dynamic>{
  'confirmation_code': instance.confirmationCode,
  'password': instance.password,
};

UsersTransferOwnerPost$RequestBody _$UsersTransferOwnerPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersTransferOwnerPost$RequestBody(userId: json['user_id'] as String);

Map<String, dynamic> _$UsersTransferOwnerPost$RequestBodyToJson(
  UsersTransferOwnerPost$RequestBody instance,
) => <String, dynamic>{'user_id': instance.userId};
