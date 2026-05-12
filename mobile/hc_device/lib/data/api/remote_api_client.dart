import 'package:hc_device/api/remote_access.swagger.dart' show RemoteAccess;
import 'package:hc_device/providers/auth.api.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:http/http.dart' as http;

class RemoteApiClientFactory {
  const RemoteApiClientFactory();

  RemoteAccess create({
    required Uri baseUrl,
    required CuratorAuthProvider authProvider,
    http.Client? httpClient,
  }) {
    return RemoteAccess.create(
      baseUrl: baseUrl,
      httpClient: httpClient,
      authenticator: CuratorAuthenticator(authProvider),
      interceptors: [CuratorInterceptor(authProvider), ...hcDeviceHttpLogInterceptors()],
    );
  }
}
