import 'package:pigeon/pigeon.dart';

class ClientCertData {
  Uint8List data;
  String password;

  ClientCertData(this.data, this.password);
}

class ClientCertPrompt {
  String title;
  String message;
  String cancel;
  String confirm;

  ClientCertPrompt(this.title, this.message, this.cancel, this.confirm);
}

class HttpRequestData {
  String method;
  String url;
  Map<String, String> headers;
  Uint8List? body;

  HttpRequestData({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });
}

class HttpResponseData {
  int statusCode;
  Map<String, String> headers;
  Uint8List body;

  HttpResponseData({
    required this.statusCode,
    required this.headers,
    required this.body,
  });
}

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/platform/network_api.g.dart',
    swiftOut: 'ios/Runner/Core/Network.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOut: 'android/app/src/main/kotlin/com/seagate/curator/stxphotos/android/core/Network.g.kt',
    kotlinOptions: KotlinOptions(package: 'com.seagate.curator.stxphotos.android.core', includeErrorClass: true),
    dartOptions: DartOptions(),
    dartPackageName: 'personal_cloud_photos',
  ),
)
@HostApi()
abstract class NetworkApi {
  @async
  void addCertificate(ClientCertData clientData);

  @async
  void selectCertificate(ClientCertPrompt promptText);

  @async
  void removeCertificate();

  bool hasCertificate();

  int getClientPointer();

  void setRequestHeaders(Map<String, String> headers, List<String> serverUrls, String? token);

  /// Installs custom root CAs (DER, base64) for the shared native HTTP client.
  void configureCertificatePinning(List<String> rootCertificatesBase64);

  /// Registers intermediate/trusted certs (DER, base64) for [host], excluding the leaf.
  void registerTrustedChain(String host, List<String> chainCertificatesBase64);

  void unregisterTrustedChain(String host);

  /// Performs an HTTP request on the shared native client (iOS URLSession / Android OkHttp).
  ///
  /// Completion is handled entirely in native code so Dart does not register FFI
  /// URLSession completion blocks (which can crash after timeouts).
  @async
  HttpResponseData sendHttpRequest(HttpRequestData request, int timeoutSeconds);
}
