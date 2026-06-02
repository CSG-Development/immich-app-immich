import 'dart:ffi';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:immich_mobile/infrastructure/repositories/native_shared_url_session_client.dart';
import 'package:immich_mobile/infrastructure/repositories/native_shared_url_session_web_socket.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:ok_http/ok_http.dart';
import 'package:web_socket/web_socket.dart';

class NetworkRepository {
  static http.Client? _client;
  static Pointer<Void>? _clientPointer;

  static Future<void> init() async {
    final clientPointer = Pointer<Void>.fromAddress(await networkApi.getClientPointer());
    if (clientPointer == _clientPointer) {
      return;
    }
    _clientPointer = clientPointer;
    _client?.close();
    if (Platform.isIOS) {
      // Use URLSessionManager's session so NetworkCertificatePinning and shared
      // cookies apply. CupertinoClient.defaultSessionConfiguration() creates a
      // separate session without the pinning delegate.
      _client = NativeSharedUrlSessionClient.fromPointer(clientPointer.address);
    } else {
      _client = OkHttpClient.fromJniGlobalRef(
        clientPointer,
        configuration: const OkHttpClientConfiguration(
          connectTimeout: Duration(seconds: 30),
          readTimeout: Duration(seconds: 60),
          writeTimeout: Duration(seconds: 60),
        ),
      );
    }
  }

  static Future<void> setHeaders(Map<String, String> headers, List<String> serverUrls, {String? token}) async {
    await networkApi.setRequestHeaders(headers, serverUrls, token);
    if (Platform.isIOS) {
      await init();
    }
  }

  static Future<WebSocket> createWebSocket(
    Uri uri, {
    Map<String, String>? headers,
    Iterable<String>? protocols,
  }) async {
    if (_clientPointer == null) {
      await init();
    }

    if (Platform.isIOS) {
      return NativeSharedUrlSessionWebSocket.connectFromPointer(
        _clientPointer!.address,
        uri,
        protocols: protocols,
        headers: headers,
      );
    }

    return OkHttpWebSocket.connectFromJniGlobalRef(
      _clientPointer!,
      uri,
      protocols: protocols,
    );
  }

  const NetworkRepository();

  /// Returns a shared HTTP client that uses native SSL configuration.
  ///
  /// On iOS: Uses SharedURLSessionManager's URLSession.
  /// On Android: Uses SharedHttpClientManager's OkHttpClient.
  ///
  /// Must call [init] before using this method.
  static http.Client get client => _client!;
}
