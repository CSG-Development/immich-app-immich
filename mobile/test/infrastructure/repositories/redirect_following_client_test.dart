import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:immich_mobile/infrastructure/repositories/redirect_following_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every request it receives and replies from a scripted queue.
class _FakeClient extends http.BaseClient {
  _FakeClient(this._responses);

  final List<http.StreamedResponse> _responses;
  final requests = <http.BaseRequest>[];
  final bodies = <List<int>>[];
  var closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(await request.finalize().toBytes());
    return _responses.removeAt(0);
  }

  @override
  void close() => closed = true;
}

http.StreamedResponse _redirect(int statusCode, String? location) =>
    http.StreamedResponse(
      const Stream<List<int>>.empty(),
      statusCode,
      headers: location == null ? {} : {'location': location},
    );

http.StreamedResponse _ok([String body = 'done']) =>
    http.StreamedResponse(Stream.value(utf8.encode(body)), 200);

void main() {
  group('RedirectFollowingClient', () {
    test('disables the native redirect loop on every request', () async {
      final inner = _FakeClient([_ok()]);
      final request = http.Request('GET', Uri.parse('https://host/a'));

      await RedirectFollowingClient(inner).send(request);

      expect(inner.requests.single.followRedirects, isFalse);
    });

    test('resolves a relative Location against the current URL', () async {
      // The exact shape that crashed the app: OkHttp rejects `/about`.
      final inner = _FakeClient([_redirect(302, '/about'), _ok()]);

      final response = await RedirectFollowingClient(
        inner,
      ).send(http.Request('GET', Uri.parse('https://192.168.1.16/api/server')));

      expect(inner.requests[1].url, Uri.parse('https://192.168.1.16/about'));
      expect(response.statusCode, 200);
    });

    test('resolves a relative Location without a leading slash', () async {
      final inner = _FakeClient([_redirect(302, 'next'), _ok()]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('GET', Uri.parse('https://host/api/server')));

      expect(inner.requests[1].url, Uri.parse('https://host/api/next'));
    });

    test('resolves each hop against the previous hop', () async {
      final inner = _FakeClient([
        _redirect(302, 'https://other/deep/page'),
        _redirect(302, 'sibling'),
        _ok(),
      ]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('GET', Uri.parse('https://host/start')));

      expect(inner.requests[2].url, Uri.parse('https://other/deep/sibling'));
    });

    test('follows an absolute Location', () async {
      final inner = _FakeClient([_redirect(302, 'https://other/x'), _ok()]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('GET', Uri.parse('https://host/a')));

      expect(inner.requests[1].url, Uri.parse('https://other/x'));
    });

    test('turns POST into GET and drops the body on 302', () async {
      final inner = _FakeClient([_redirect(302, '/about'), _ok()]);
      final request = http.Request('POST', Uri.parse('https://host/a'))
        ..body = 'payload';

      await RedirectFollowingClient(inner).send(request);

      expect(inner.requests[1].method, 'GET');
      expect(inner.bodies[1], isEmpty);
      expect(inner.requests[1].headers.containsKey('content-type'), isFalse);
    });

    test('turns POST into GET on 303', () async {
      final inner = _FakeClient([_redirect(303, '/about'), _ok()]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('POST', Uri.parse('https://host/a'))..body = 'x');

      expect(inner.requests[1].method, 'GET');
    });

    test('preserves method and body on 307', () async {
      final inner = _FakeClient([_redirect(307, '/about'), _ok()]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('POST', Uri.parse('https://host/a'))..body = 'keep');

      expect(inner.requests[1].method, 'POST');
      expect(utf8.decode(inner.bodies[1]), 'keep');
    });

    test('preserves method and body on 308', () async {
      final inner = _FakeClient([_redirect(308, '/about'), _ok()]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('PUT', Uri.parse('https://host/a'))..body = 'keep');

      expect(inner.requests[1].method, 'PUT');
      expect(utf8.decode(inner.bodies[1]), 'keep');
    });

    test('keeps HEAD as HEAD on 303', () async {
      final inner = _FakeClient([_redirect(303, '/about'), _ok()]);

      await RedirectFollowingClient(
        inner,
      ).send(http.Request('HEAD', Uri.parse('https://host/a')));

      expect(inner.requests[1].method, 'HEAD');
    });

    test('carries headers across a redirect', () async {
      final inner = _FakeClient([_redirect(302, '/about'), _ok()]);
      final request = http.Request('GET', Uri.parse('https://host/a'))
        ..headers['x-immich-user-token'] = 'secret';

      await RedirectFollowingClient(inner).send(request);

      expect(inner.requests[1].headers['x-immich-user-token'], 'secret');
    });

    test('returns the 3xx when followRedirects is false', () async {
      final inner = _FakeClient([_redirect(302, '/about')]);
      final request = http.Request('GET', Uri.parse('https://host/a'))
        ..followRedirects = false;

      final response = await RedirectFollowingClient(inner).send(request);

      expect(response.statusCode, 302);
      expect(inner.requests, hasLength(1));
    });

    test('returns the 3xx when Location is missing', () async {
      final inner = _FakeClient([_redirect(302, null)]);

      final response = await RedirectFollowingClient(
        inner,
      ).send(http.Request('GET', Uri.parse('https://host/a')));

      expect(response.statusCode, 302);
      expect(inner.requests, hasLength(1));
    });

    test('returns the 3xx for a non-http scheme', () async {
      final inner = _FakeClient([_redirect(302, 'ftp://host/x')]);

      final response = await RedirectFollowingClient(
        inner,
      ).send(http.Request('GET', Uri.parse('https://host/a')));

      expect(response.statusCode, 302);
      expect(inner.requests, hasLength(1));
    });

    test('returns the 3xx when a streamed body cannot be replayed', () async {
      // 307 preserves the method, so the consumed body would be needed again.
      final inner = _FakeClient([_redirect(307, '/about')]);
      final request = http.StreamedRequest('POST', Uri.parse('https://host/a'));
      request.sink.add(utf8.encode('chunk'));
      unawaited(request.sink.close());

      final response = await RedirectFollowingClient(inner).send(request);

      expect(response.statusCode, 307);
      expect(inner.requests, hasLength(1));
    });

    test('follows a streamed request when the body is dropped', () async {
      final inner = _FakeClient([_redirect(302, '/about'), _ok()]);
      final request = http.StreamedRequest('POST', Uri.parse('https://host/a'));
      request.sink.add(utf8.encode('chunk'));
      unawaited(request.sink.close());

      final response = await RedirectFollowingClient(inner).send(request);

      expect(inner.requests[1].method, 'GET');
      expect(response.statusCode, 200);
    });

    test('follows up to maxRedirects hops', () async {
      final inner = _FakeClient([
        _redirect(302, '/1'),
        _redirect(302, '/2'),
        _ok(),
      ]);
      final request = http.Request('GET', Uri.parse('https://host/a'))
        ..maxRedirects = 2;

      final response = await RedirectFollowingClient(inner).send(request);

      expect(response.statusCode, 200);
    });

    test('throws once maxRedirects is exceeded', () async {
      final inner = _FakeClient([
        _redirect(302, '/1'),
        _redirect(302, '/2'),
        _redirect(302, '/3'),
      ]);
      final request = http.Request('GET', Uri.parse('https://host/a'))
        ..maxRedirects = 2;

      await expectLater(
        RedirectFollowingClient(inner).send(request),
        throwsA(
          isA<http.ClientException>().having(
            (e) => e.message,
            'message',
            'Redirect limit exceeded',
          ),
        ),
      );
    });

    test('closes the inner client', () {
      final inner = _FakeClient([]);

      RedirectFollowingClient(inner).close();

      expect(inner.closed, isTrue);
    });
  });
}
