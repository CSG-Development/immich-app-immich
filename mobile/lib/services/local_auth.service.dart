import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:logging/logging.dart';

class LocalAuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final log = Logger("LocalAuthService");

  Future<bool> isBiometricAvailable() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException catch (e) {
      log.severe('Error checking biometric availability', e);
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException catch (e) {
      log.severe('Error getting available biometrics', e);
      return [];
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Authenticate to access your photos',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } on PlatformException catch (e) {
      log.severe('Error authenticating with biometrics', e);
      return false;
    }
  }
} 