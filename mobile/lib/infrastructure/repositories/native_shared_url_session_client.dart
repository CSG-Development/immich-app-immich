import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/platform/network_api.g.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:hc_device/services/request_timeout_interceptor.dart';
import 'package:immich_mobile/utils/async_mutex.dart';

/// HTTP [Client] backed by the shared URLSession so SSL pinning,
/// client certificates, and shared auth cookies apply to API traffic.
///
/// iOS requests are executed via pigeon [NetworkApi.sendHttpRequest] so URLSession
/// completion handlers stay in Swift. Dart FFI completion blocks can crash with
/// "Callback invoked after it has been deleted" when LAN probes time out.
class NativeSharedUrlSessionClient extends BaseClient {
  /// Client-side timeout hint (seconds). Stripped before the request hits the wire.
  ///
  /// Set by [CuratorRequestTimeoutInterceptor] in hc_device path probes.
  static const requestTimeoutHeader = CuratorRequestTimeoutInterceptor.headerName;

  static const Duration _defaultTimeout = Duration(seconds: 60);

  /// Serializes pigeon platform-channel replies during parallel path probing.
  static final _pigeonRequestMutex = AsyncMutex();

  NativeSharedUrlSessionClient._();

  /// [sessionPointerAddress] is unused for HTTP; kept for API compatibility with
  /// [NetworkRepository.init], which shares the session pointer with WebSockets.
  factory NativeSharedUrlSessionClient.fromPointer(int sessionPointerAddress) {
    return NativeSharedUrlSessionClient._();
  }

  @override
  void close() {
    // Owned by the native singleton; do not invalidate.
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final body = request is Request
        ? request.bodyBytes
        : await request.finalize().toBytes();

    final headers = Map<String, String>.from(request.headers);
    var timeout = _defaultTimeout;
    headers.removeWhere((name, value) {
      if (name.toLowerCase() != requestTimeoutHeader) {
        return false;
      }
      final seconds = int.tryParse(value);
      if (seconds != null && seconds > 0) {
        timeout = Duration(seconds: seconds);
      }
      return true;
    });

    return _pigeonRequestMutex.run(() async {
      try {
        final response = await networkApi.sendHttpRequest(
          HttpRequestData(
            method: request.method,
            url: request.url.toString(),
            headers: headers,
            body: body.isEmpty ? null : body,
          ),
          timeout.inSeconds,
        );

        return StreamedResponse(
          Stream.value(response.body),
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      } on PlatformException catch (error) {
        throw ClientException(error.message ?? 'HTTP request failed', request.url);
      }
    });
  }
}
