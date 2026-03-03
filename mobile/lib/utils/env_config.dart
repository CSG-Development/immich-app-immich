import 'package:flutter/services.dart' as services;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';

enum AppEnvironment {
  dev,
  prod,
}

enum EnvKey {
  updateUrl('UPDATE_URL'),
  devEmail('DEV_EMAIL'),
  devPassword('DEV_PASSWORD');

  const EnvKey(this.key);
  final String key;
}

class EnvConfig {
  EnvConfig._();

  static final Logger _log = Logger('EnvConfig');

  /// App flavor provided by native code (`package:flutter/services.dart`).
  /// This can be `null` when no flavor is configured on the native side.
  static String? get appFlavor => services.appFlavor;

  /// Strongly-typed environment, derived from the native flavor name.
  /// If the native flavor name contains "dev" (case-insensitive), we treat it
  /// as the "dev" environment; otherwise we fall back to "prod".
  static AppEnvironment get environment {
    final flavor = appFlavor;
    final isDev = flavor?.toLowerCase().contains('dev') == true;
    return isDev ? AppEnvironment.dev : AppEnvironment.prod;
  }

  /// Logical environment name used for `.env.<env>` files.
  static String get envName {
    switch (environment) {
      case AppEnvironment.dev:
        return 'dev';
      case AppEnvironment.prod:
        return 'prod';
    }
  }

  /// File name of the environment file to load.
  static String get envFileName => '.env.$envName';

  /// Ensure that the dotenv environment file for the current flavor is loaded.
  static Future<void> ensureLoaded() async {
    if (dotenv.isInitialized) {
      return;
    }

    try {
      await dotenv.load(fileName: envFileName);
      _log.info('Loaded env file $envFileName for flavor: $appFlavor');
    } catch (error, stackTrace) {
      _log.severe(
        'Failed to load env file $envFileName for flavor: $appFlavor',
        error,
        stackTrace,
      );
    }
  }

  /// Get an environment value by key, making sure the correct file is loaded first.
  static Future<String?> get(EnvKey key) async {
    await ensureLoaded();
    return dotenv.env[key.key];
  }
}

