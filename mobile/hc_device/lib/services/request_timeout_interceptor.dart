import 'dart:async';

import 'package:chopper/chopper.dart';

/// Sets a client-side request timeout consumed by the native HTTP client.
///
/// The header is stripped before the request is sent to the device.
class CuratorRequestTimeoutInterceptor implements Interceptor {
  const CuratorRequestTimeoutInterceptor(this.timeout);

  static const headerName = 'x-curator-request-timeout-seconds';

  final Duration timeout;

  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) {
    return chain.proceed(
      applyHeader(
        chain.request,
        headerName,
        '${timeout.inSeconds}',
      ),
    );
  }
}
