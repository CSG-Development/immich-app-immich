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

DeviceConfiguration _$DeviceConfigurationFromJson(Map<String, dynamic> json) =>
    DeviceConfiguration(
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
      secureBootEnabled: json['secure_boot_enabled'] as bool,
    );

Map<String, dynamic> _$DeviceConfigurationToJson(
  DeviceConfiguration instance,
) => <String, dynamic>{
  'device_certificate_signed_by': instance.deviceCertificateSignedBy?.toJson(),
  'prod_failure_reasons': instance.prodFailureReasons,
  'prod_ready': instance.prodReady,
  'provisioning_vault': instance.provisioningVault.toJson(),
  'secure_boot_enabled': instance.secureBootEnabled,
};

DeviceConfigurationCertificate _$DeviceConfigurationCertificateFromJson(
  Map<String, dynamic> json,
) => DeviceConfigurationCertificate(
  name: json['name'] as String,
  $value: json['value'] as String,
);

Map<String, dynamic> _$DeviceConfigurationCertificateToJson(
  DeviceConfigurationCertificate instance,
) => <String, dynamic>{'name': instance.name, 'value': instance.$value};

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
  'certificates': instance.certificates.map((e) => e.toJson()).toList(),
  'creation_date': instance.creationDate.toIso8601String(),
  'signed_by': instance.signedBy.toJson(),
};

Error _$ErrorFromJson(Map<String, dynamic> json) =>
    Error(error: json['error'] as String, message: json['message'] as String);

Map<String, dynamic> _$ErrorToJson(Error instance) => <String, dynamic>{
  'error': instance.error,
  'message': instance.message,
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

Hello _$HelloFromJson(Map<String, dynamic> json) =>
    Hello(world: json['world'] as String);

Map<String, dynamic> _$HelloToJson(Hello instance) => <String, dynamic>{
  'world': instance.world,
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
);

Map<String, dynamic> _$InviteToJson(Invite instance) => <String, dynamic>{
  'creation_date': instance.creationDate.toIso8601String(),
  'email': instance.email,
};

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
    );

Map<String, dynamic> _$NetworkInterfaceToJson(NetworkInterface instance) =>
    <String, dynamic>{
      'hardware_info': instance.hardwareInfo.toJson(),
      'ipv4_info': instance.ipv4Info?.toJson(),
      'link_info': instance.linkInfo?.toJson(),
      'name': instance.name,
      'type': networkInterfaceTypeToJson(instance.type),
    };

Oobe _$OobeFromJson(Map<String, dynamic> json) =>
    Oobe(done: json['done'] as bool);

Map<String, dynamic> _$OobeToJson(Oobe instance) => <String, dynamic>{
  'done': instance.done,
};

SMTPConfig _$SMTPConfigFromJson(Map<String, dynamic> json) => SMTPConfig(
  password: json['password'] as String,
  port: (json['port'] as num).toInt(),
  server: json['server'] as String,
  user: json['user'] as String,
);

Map<String, dynamic> _$SMTPConfigToJson(SMTPConfig instance) =>
    <String, dynamic>{
      'password': instance.password,
      'port': instance.port,
      'server': instance.server,
      'user': instance.user,
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

WifiConfig _$WifiConfigFromJson(Map<String, dynamic> json) => WifiConfig(
  ssid: json['SSID'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$WifiConfigToJson(WifiConfig instance) =>
    <String, dynamic>{'SSID': instance.ssid, 'password': instance.password};

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
  email: json['email'] as String?,
  isAdmin: json['is_admin'] as bool?,
  name: json['name'] as String?,
  oldPassword: json['old_password'] as String?,
  password: json['password'] as String?,
);

Map<String, dynamic> _$UsersIdPut$RequestBodyToJson(
  UsersIdPut$RequestBody instance,
) => <String, dynamic>{
  'email': instance.email,
  'is_admin': instance.isAdmin,
  'name': instance.name,
  'old_password': instance.oldPassword,
  'password': instance.password,
};

UsersInvitesPost$RequestBody _$UsersInvitesPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersInvitesPost$RequestBody(email: json['email'] as String);

Map<String, dynamic> _$UsersInvitesPost$RequestBodyToJson(
  UsersInvitesPost$RequestBody instance,
) => <String, dynamic>{'email': instance.email};

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
  email: json['email'] as String?,
  isAdmin: json['is_admin'] as bool?,
  name: json['name'] as String?,
  oldPassword: json['old_password'] as String?,
  password: json['password'] as String?,
);

Map<String, dynamic> _$UsersMePut$RequestBodyToJson(
  UsersMePut$RequestBody instance,
) => <String, dynamic>{
  'email': instance.email,
  'is_admin': instance.isAdmin,
  'name': instance.name,
  'old_password': instance.oldPassword,
  'password': instance.password,
};

UsersOwnerPost$RequestBody _$UsersOwnerPost$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersOwnerPost$RequestBody(
  email: json['email'] as String,
  name: json['name'] as String,
  password: json['password'] as String,
);

Map<String, dynamic> _$UsersOwnerPost$RequestBodyToJson(
  UsersOwnerPost$RequestBody instance,
) => <String, dynamic>{
  'email': instance.email,
  'name': instance.name,
  'password': instance.password,
};

UsersOwnerPut$RequestBody _$UsersOwnerPut$RequestBodyFromJson(
  Map<String, dynamic> json,
) => UsersOwnerPut$RequestBody(
  confirmationCode: json['confirmation_code'] as String,
);

Map<String, dynamic> _$UsersOwnerPut$RequestBodyToJson(
  UsersOwnerPut$RequestBody instance,
) => <String, dynamic>{'confirmation_code': instance.confirmationCode};
