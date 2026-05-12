import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hc_device/services/logger_service.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

class AuthRepository {
  const AuthRepository(this._secureStorage);

  final FlutterSecureStorage? _secureStorage;

  Future<void> writeSharedString(String key, String value) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(key, value);
  }

  Future<void> removeSharedString(String key) async {
    final prefs = SharedPreferencesAsync();
    await prefs.remove(key);
  }

  Future<void> writeSecureString(String key, String value) async {
    try {
      await _secureStorage?.write(key: key, value: value);
    } catch (e) {
      logger.error('[Security] Failed to write secure storage key "$key"', e);
    }
  }

  Future<void> deleteSecureString(String key) async {
    try {
      await _secureStorage?.delete(key: key);
    } catch (e) {
      logger.error('[Security] Failed to delete secure storage key "$key"', e);
    }
  }
}
