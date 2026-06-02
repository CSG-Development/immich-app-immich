import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:cupertino_http/cupertino_http.dart';
import 'package:cupertino_http/src/native_cupertino_bindings.dart' as ncb;
import 'package:objective_c/objective_c.dart' as objc;
import 'package:web_socket/web_socket.dart';

/// WebSocket backed by the shared URLSession so SSL pinning and auth cookies apply.
class NativeSharedUrlSessionWebSocket implements WebSocket {
  static Future<WebSocket> connectFromPointer(
    int sessionPointerAddress,
    Uri url, {
    Iterable<String>? protocols,
    Map<String, String>? headers,
  }) async {
    if (!url.isScheme('ws') && !url.isScheme('wss')) {
      throw ArgumentError.value(url, 'url', 'only ws: and wss: schemes are supported');
    }

    final session = ncb.NSURLSession.fromPointer(
      Pointer.fromAddress(sessionPointerAddress),
      retain: false,
      release: false,
    );

    final nsUrl = objc.NSURL.URLWithString(url.toString().toNSString());
    if (nsUrl == null) {
      throw ArgumentError.value(url, 'url', 'invalid URL');
    }

    final nsRequest = ncb.NSMutableURLRequest.requestWithURL(nsUrl);
    headers?.forEach((name, value) {
      nsRequest.setValue(value.toNSString(), forHTTPHeaderField: name.toNSString());
    });
    if (protocols != null && protocols.isNotEmpty) {
      nsRequest.setValue(
        protocols.join(',').toNSString(),
        forHTTPHeaderField: 'Sec-WebSocket-Protocol'.toNSString(),
      );
    }

    final task = session.webSocketTaskWithRequest(nsRequest);
    task.resume();
    await _waitForTaskRunning(task);

    return NativeSharedUrlSessionWebSocket._(task, '');
  }

  static Future<void> _waitForTaskRunning(ncb.NSURLSessionWebSocketTask task) async {
    const pollInterval = Duration(milliseconds: 25);
    const maxWait = Duration(seconds: 30);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      final state = task.state;
      if (state == NSURLSessionTaskState.NSURLSessionTaskStateRunning) {
        return;
      }
      if (state == NSURLSessionTaskState.NSURLSessionTaskStateCompleted) {
        final error = task.error;
        if (error != null) {
          throw ConnectionException('WebSocket connection failed', error);
        }
        throw StateError('WebSocket task completed before running');
      }
      await Future.delayed(pollInterval);
    }

    throw TimeoutException('WebSocket connection timed out', maxWait);
  }

  final ncb.NSURLSessionWebSocketTask _task;
  final String _protocol;
  final _events = StreamController<WebSocketEvent>();

  NativeSharedUrlSessionWebSocket._(this._task, this._protocol) {
    _scheduleReceive();
  }

  void _handleMessage(ncb.NSURLSessionWebSocketMessage value) {
    if (_events.isClosed) return;

    late WebSocketEvent event;
    switch (value.type) {
      case NSURLSessionWebSocketMessageType.NSURLSessionWebSocketMessageTypeString:
        event = TextDataReceived(value.string!.toDartString());
      case NSURLSessionWebSocketMessageType.NSURLSessionWebSocketMessageTypeData:
        event = BinaryDataReceived(value.data!.toList());
    }
    _events.add(event);
    _scheduleReceive();
  }

  void _scheduleReceive() {
    unawaited(
      _receiveMessage().then(
        _handleMessage,
        onError: _closeConnectionWithError,
      ),
    );
  }

  Future<ncb.NSURLSessionWebSocketMessage> _receiveMessage() async {
    final completer = Completer<ncb.NSURLSessionWebSocketMessage>();
    _task.receiveMessageWithCompletionHandler(
      ncb.ObjCBlock_ffiVoid_NSURLSessionWebSocketMessage_NSError.listener((
        message,
        error,
      ) {
        if (error != null) {
          completer.completeError(error);
        } else if (message != null) {
          completer.complete(message);
        } else {
          completer.completeError(StateError('one of message or error must be non-null'));
        }
      }),
    );
    return completer.future;
  }

  Future<void> _sendMessage(ncb.NSURLSessionWebSocketMessage message) async {
    final completer = Completer<void>();
    _task.sendMessage(
      message,
      completionHandler: ncb.ObjCBlock_ffiVoid_NSError.listener((error) {
        if (error == null) {
          completer.complete();
        } else {
          completer.completeError(error);
        }
      }),
    );
    await completer.future;
  }

  void _closeConnectionWithError(Object e) {
    if (e is objc.NSError) {
      final domain = e.domain.toDartString();
      if (domain == 'NSPOSIXErrorDomain' && e.code == 57) {
        return;
      }
      final (int code, String reason) = switch ([domain, e.code]) {
        ['NSPOSIXErrorDomain', 100] => (1002, e.localizedDescription.toDartString()),
        _ => (1006, e.localizedDescription.toDartString()),
      };
      _task.cancel();
      _connectionClosed(code, reason.codeUnits.toNSData());
    } else {
      throw StateError('unexpected error: $e');
    }
  }

  void _connectionClosed(int? closeCode, objc.NSData? reason) {
    if (!_events.isClosed) {
      final closeReason = reason == null ? '' : utf8.decode(reason.toList());
      _events
        ..add(CloseReceived(closeCode, closeReason))
        ..close();
    }
  }

  @override
  void sendBytes(Uint8List b) {
    if (_events.isClosed) {
      throw WebSocketConnectionClosed();
    }
    unawaited(
      _sendMessage(
        ncb.NSURLSessionWebSocketMessage.alloc().initWithData(b.toNSData()),
      ).catchError(_closeConnectionWithError),
    );
  }

  @override
  void sendText(String s) {
    if (_events.isClosed) {
      throw WebSocketConnectionClosed();
    }
    unawaited(
      _sendMessage(
        ncb.NSURLSessionWebSocketMessage.alloc().initWithString(s.toNSString()),
      ).catchError(_closeConnectionWithError),
    );
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    if (_events.isClosed) {
      throw WebSocketConnectionClosed();
    }

    if (code != null && code != 1000 && !(code >= 3000 && code <= 4999)) {
      throw ArgumentError('Invalid argument: $code, close code must be 1000 or in the range 3000-4999');
    }
    if (reason != null && utf8.encode(reason).length > 123) {
      throw ArgumentError.value(reason, 'reason', 'reason must be <= 123 bytes long when encoded as UTF-8');
    }

    if (!_events.isClosed) {
      unawaited(_events.close());
      if (code != null) {
        reason = reason ?? '';
        _task.cancelWithCloseCode(code, reason: utf8.encode(reason).toNSData());
      } else {
        _task.cancel();
      }
    }
  }

  @override
  Stream<WebSocketEvent> get events => _events.stream;

  @override
  String get protocol => _protocol;
}
