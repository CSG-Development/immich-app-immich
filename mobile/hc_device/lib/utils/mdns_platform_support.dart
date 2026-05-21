import 'package:flutter/services.dart';

bool get canUsePlatformMdnsDiscovery => RootIsolateToken.instance != null;
