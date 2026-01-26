import 'package:flutter/foundation.dart';

import 'dart:convert' show jsonDecode;

import 'package:chopper/chopper.dart' show Response;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hc_device/api/remote_access.swagger.dart' as api show Error;
import 'package:hc_device/providers/hcdevice.provider.dart';

import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart' show SharedPreferencesAsync;

enum ApiErrorMessage { aboutGet, statusGet, remoteApi }

const String serviceTypeDiscover = '_https._tcp';
const String serviceNameDiscover = 'HomeCloud';
const Duration durationDetection = Duration(seconds: 4);

String extractErrorMessage(dynamic e) {
  late String? message = "";
  try {
    if (e is Exception) {
      if (kDebugMode) {
        print(e);
      }
      // Extract error from BlueTooth API
      if (e is PlatformException) {
        message = e.message;
      }
    }
    // Extract error from API response
    else if (e is Response) {
      try {
        final error = convertError(e);
        // Try to extract 'reason' or 'stacktrace' from the error response
        message = error.reason != null && error.reason!.isNotEmpty ? error.reason : error.stacktrace;
        if (message != null && message.contains(':')) {
          message = message.split(':').last.trim();
        }
        // Fallback to the full error response
        if (message == null || message.isEmpty) {
          message = e.error.toString();
        }
      } catch (decodeError) {
        if (kDebugMode) {
          print("Error extracting message: $decodeError");
        }
        message = "${e.statusCode}";
        if (e.error is String && (e.error as String).isNotEmpty) {
          message += ": ${e.error}";
        }
      }
    }
  } catch (e) {
    if (kDebugMode) {
      print("Error extracting message: $e");
    }
  }
  if (message == null || message.isEmpty) {
    message = e.toString();
  }
  return message;
}

api.Error convertError(Response response) {
  try {
    if (kDebugMode) {
      print(
        "API ${response.base.request?.url.toString().split('api').last} failed with status [${response.statusCode}]: ${response.error}",
      );
    }
    return api.Error.fromJson(jsonDecode(response.error.toString()));
  } catch (e) {
    if (kDebugMode) {
      print("Error converting response error: $e");
    }
    return api.Error(name: "Unknown error", stacktrace: response.error.toString());
  }
}

Future<nsd.Discovery?> startDiscovery() async {
  try {
    return await nsd.startDiscovery(serviceTypeDiscover, autoResolve: true, ipLookupType: nsd.IpLookupType.v4);
  } catch (e) {
    if (kDebugMode) {
      print("[SignInScreen] NSD Start Discovery Error: $e");
    }
  }
  return null;
}

Future<void> stopDiscovery(nsd.Discovery discovery) async {
  try {
    await nsd.stopDiscovery(discovery);
  } catch (e) {
    // TODO Fix error on Android:
    // NsdError (message: "stopDiscovery: MulticastLock under-locked nsdMulticastLock", cause: internalError)
    if (kDebugMode) {
      print("[SignInScreen] NSD Stop Discovery Error: $e");
    }
  }
}

Future<RemoteAccessDependencies> initHCDevice({dynamic registerHostTrustedChain}) async {
  final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
  final Map<String, dynamic> storageData = await asyncPrefs.getAll();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  late Map<String, String> secureData;

  // Check if this is the first launch (after reinstall)
  const String hasLaunchedBeforeKey = 'homecloud_has_launched_before';
  final bool hasLaunchedBefore = storageData.containsKey(hasLaunchedBeforeKey);

  if (!hasLaunchedBefore) {
    // This is a fresh install or reinstall - clear secure storage
    try {
      await secureStorage.deleteAll();
    } catch (e) {
      // If clearing secure storage fails, continue with existing data
    }
    // Mark that the app has been launched
    await asyncPrefs.setBool(hasLaunchedBeforeKey, true);
  }

  try {
    secureData = await secureStorage.readAll();
  } catch (e) {
    // If reading secure storage fails, initialize with an empty map
    secureData = {};
  }

  return RemoteAccessDependencies(
    secureData: secureData,
    secureStorage: secureStorage,
    storageData: storageData,
    registerHostTrustedChain: registerHostTrustedChain
  );
}
