import 'package:hc_device/api/remote_access.swagger.dart' show RemoteAccess;
import 'package:hc_device/providers/auth.api.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:hc_device/services/request_timeout_interceptor.dart';
import 'package:http/http.dart' as http;

const Duration remoteAccessApiTimeout = Duration(seconds: 9);

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
      interceptors: [
        const CuratorRequestTimeoutInterceptor(remoteAccessApiTimeout),
        CuratorInterceptor(authProvider),
        ...hcDeviceHttpLogInterceptors(),
      ],
    );
  }
}
