import 'package:basic_utils/basic_utils.dart' show X509Utils, X509CertificateData;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'dart:convert' show jsonDecode;

import 'package:chopper/chopper.dart' show Response;
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart' as api show Error;
import 'package:homecloud_frontend/providers/hcdevice.provider.dart';

import 'package:nsd/nsd.dart' as nsd;
import 'package:shared_preferences/shared_preferences.dart';

enum ApiErrorMessage { aboutGet, statusGet, remoteApi }

const String serviceTypeDiscover = '_https._tcp';
const String serviceNameDiscover = 'HomeCloud';
const Duration durationDetection = Duration(seconds: 4);

/// Initialize the certificates used to validate the Home Cloud server certificate
Future<X509CertificateData?> initializeHomecloudCertificate() async {
  try {
    // FIXME replace with production certificate (tdci.cer)
    String pem = await rootBundle.loadString('assets/fake-device-noveo.cer');
    return X509Utils.x509CertificateFromPem(pem);
  } catch (e) {
    if (kDebugMode) {
      debugPrint("[Certificate] Unable to load root certificates: ${e.toString()}");
    }
    return null;
  }
}

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

Future<RemoteAccessDependencies> initHCDevice() async {
  // Initialize Homecloud certificate for TLS validation
  final homecloudCert = await initializeHomecloudCertificate();

  final Map<String, dynamic> storageData = await SharedPreferencesAsync().getAll();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  late Map<String, String> secureData;

  try {
    secureData = await secureStorage.readAll();
  } catch (e) {
    // If reading secure storage fails, initialize with an empty map
    secureData = {};
    if (kDebugMode) {
      print("Error reading secure storage: $e");
    }
  }

  return RemoteAccessDependencies(
    secureData: secureData,
    secureStorage: secureStorage,
    storageData: storageData,
    deviceCertificate: homecloudCert!,
  );
}
