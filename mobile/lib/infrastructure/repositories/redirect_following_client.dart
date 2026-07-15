import 'dart:async';

import 'package:http/http.dart' as http;

/// Redirect status codes that carry a `Location` header.
const _redirectStatusCodes = {301, 302, 303, 307, 308};

/// Follows redirects in Dart rather than letting the native client do it.
///
/// `package:ok_http` hands the raw `Location` header to OkHttp's
/// `Request.Builder.url()`, which rejects anything without an absolute scheme.
/// A relative `Location` — which RFC 9110 §10.2.2 explicitly permits — throws
/// `IllegalArgumentException` on an OkHttp dispatcher thread; OkHttp rethrows it
/// out of `AsyncCall.run()`, where it becomes an uncaught exception and kills
/// the process. Setting [http.BaseRequest.followRedirects] to `false` keeps that
/// native loop from running at all, so the redirect is resolved here instead,
/// against the current request URL.
///
/// Method rewriting matches NSURLSession (and browsers), so Android behaves the
/// same as the iOS `CupertinoClient` path.
class RedirectFollowingClient extends http.BaseClient {
  RedirectFollowingClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final followRedirects = request.followRedirects;
    final maxRedirects = request.maxRedirects;

    // Disables the native redirect loop; every hop is issued from here.
    request.followRedirects = false;

    var current = request;
    var response = await _inner.send(current);
    if (!followRedirects) {
      return response;
    }

    var redirectCount = 0;
    while (_redirectStatusCodes.contains(response.statusCode)) {
      final location = response.headers['location'];
      if (location == null) {
        return response;
      }

      final next = _redirectRequest(current, response.statusCode, location);
      // Unresolvable target, or a body we cannot replay: surface the 3xx as-is
      // rather than guessing.
      if (next == null) {
        return response;
      }

      if (redirectCount >= maxRedirects) {
        await response.stream.drain<void>();
        throw http.ClientException('Redirect limit exceeded', request.url);
      }

      // Intermediate bodies must be consumed or the connection is never
      // returned to OkHttp's pool.
      await response.stream.drain<void>();

      response = await _inner.send(next);
      current = next;
      redirectCount++;
    }

    return response;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }

  /// Builds the follow-up request, or `null` if the redirect cannot be followed.
  http.BaseRequest? _redirectRequest(
    http.BaseRequest current,
    int statusCode,
    String location,
  ) {
    final Uri url;
    try {
      url = current.url.resolve(location);
    } on FormatException {
      return null;
    }
    if (url.scheme != 'http' && url.scheme != 'https') {
      return null;
    }

    final method = _redirectMethod(current.method, statusCode);

    // The method changed (POST -> GET), so the body is dropped. Any request
    // type can be replayed this way, including streamed and multipart ones.
    if (method != current.method) {
      return _copyRequest(current, method, url)
        ..headers.remove('content-type')
        ..headers.remove('content-length');
    }

    // Method preserved, so the body must be replayed. Only [http.Request] keeps
    // its bytes; streamed bodies are already consumed by the first hop.
    if (current is http.Request) {
      return _copyRequest(current, method, url)..bodyBytes = current.bodyBytes;
    }

    return null;
  }

  http.Request _copyRequest(http.BaseRequest current, String method, Uri url) =>
      http.Request(method, url)
        ..followRedirects = false
        ..maxRedirects = current.maxRedirects
        ..persistentConnection = current.persistentConnection
        ..headers.addAll(current.headers);

  /// Per RFC 9110 §15.4: 303 always becomes a safe method, 301/302 turn POST
  /// into GET for historical reasons, and 307/308 preserve the method.
  String _redirectMethod(String method, int statusCode) {
    if (statusCode == 307 || statusCode == 308) {
      return method;
    }
    if (method == 'HEAD') {
      return method;
    }
    if (statusCode == 303) {
      return 'GET';
    }
    return method == 'POST' ? 'GET' : method;
  }
}
