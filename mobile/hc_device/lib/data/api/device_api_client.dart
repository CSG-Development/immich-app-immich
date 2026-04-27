import 'package:hc_device/api/api.swagger.dart' show Api;
import 'package:hc_device/providers/auth.api.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:http/http.dart' as http;
import 'package:chopper/chopper.dart' show Authenticator, Interceptor;

class DeviceApiClientFactory {
  const DeviceApiClientFactory();

  Api create({
    required Uri baseUrl,
    required CuratorAuthProvider authProvider,
    http.Client? httpClient,
    Authenticator? authenticator,
    List<Interceptor>? interceptors,
  }) {
    final effectiveAuthenticator = authenticator ?? CuratorAuthenticator(authProvider);
    final effectiveInterceptors =
        interceptors ?? [CuratorInterceptor(authProvider), ...hcDeviceHttpLogInterceptors()];
    return Api.create(
      httpClient: httpClient,
      baseUrl: baseUrl,
      authenticator: effectiveAuthenticator,
      interceptors: effectiveInterceptors,
    );
  }
}
