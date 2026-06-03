import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' hide Request, Response, Notification;

import 'locks.dart';
import 'protocol.dart';
import 'types.dart';

const _disconnectMessage = '_disconnect';
final Random _random = Random();

@JS()
@anonymous
extension type WebEndpoint._(JSObject _) implements JSObject {
  external MessagePort get port;
  external String? get lockName;

  external factory WebEndpoint({
    required MessagePort port,
    required String? lockName,
  });

  ConnectableChannel connect() {
    return ConnectableChannel._(port, lockName, null);
  }
}

final class ConnectableChannel {
  final MessagePort localPort;
  final String? lockName;
  final HeldLock? lock;
  EventTarget? injectErrors;

  ConnectableChannel._(this.localPort, this.lockName, this.lock);
}

Future<(WebEndpoint, ConnectableChannel)> createChannel() async {
  final webChannel = MessageChannel();
  final locks = WebLocks.instance;

  // For servers, it's useful to know when a connection is closed, so that it
  // can release locks or otherwise clean up resources occupied by the
  // connection. This is kind of tricky for message ports, because they have
  // no "closed" event.
  // As a workaround, we're making one side take a unique lock and tell the
  // other endpoint about it. When that side closes for any reason, even just
  // because the tab is improperly closed, the other end will be able to take
  // the lock and thus know that the connection has been closed.
  HeldLock? lock;
  String? lockName;
  if (locks != null) {
    lockName = _randomLockName();
    lock = await locks.request(lockName);
  }

  final channel = ConnectableChannel._(webChannel.port2, lockName, lock);
  return (WebEndpoint(port: webChannel.port1, lockName: lockName), channel);
}

String _randomLockName() {
  final buffer = StringBuffer('channel-close-');
  for (var i = 0; i < 16; i++) {
    const charCodeSmallA = 97;
    buffer.writeCharCode(charCodeSmallA + _random.nextInt(26));
  }

  return buffer.toString();
}

abstract base class ProtocolChannel extends RequestHandler {
  final MessagePort _port;
  final Completer<void> _closed = Completer();
  StreamSubscription<void>? _incomingMessagesSubscription;
  StreamSubscription<void>? _errorSubscription;

  var _nextRequestId = 0;
  final Map<int, Completer<Response>> _responses = {};

  /// Requests that are currently being handled, identified by their id. This
  /// allows aborting them.
  final Map<int, AbortController> _handlingRequests = {};

  ProtocolChannel(ConnectableChannel connectable)
    : _port = connectable.localPort {
    _port.start();

    _incomingMessagesSubscription = EventStreamProviders.messageEvent
        .forTarget(_port)
        .listen((event) {
          final data = event.data;
          if (data.equals(_disconnectMessage.toJS).toDart) {
            _markClosed();
            return;
          }

          _handleIncoming(event.data as Message);
        });

    if (connectable.injectErrors case final injectErrors?) {
      _errorSubscription = EventStreamProviders.errorEvent
          .forTarget(injectErrors)
          .listen((event) {
            final error = (event as ErrorEvent).error;
            _markClosed(error);
          });
    }

    final lockName = connectable.lockName;
    if (connectable.lock == null && lockName != null) {
      // Once this side is able to acquire the lock, the connection is closed.
      WebLocks.instance!.request(lockName).then((lock) {
        _markClosed();
        lock.release();
      });
    }
  }

  Future<void> get closed => _closed.future;

  void _send(Message message) {
    message.sendToPort(_port);
  }

  /// Handle an incoming message from the client.
  void _handleIncoming(Message message) async {
    dispatchMessage(
      message,
      whenResponse: (response) {
        _responses.remove(response.requestId)?.complete(response);
      },
      whenRequest: (request) async {
        Response response;

        final requestId = request.requestId;
        final abortController = _handlingRequests[requestId] =
            AbortController();

        try {
          response = await dispatchRequest(request, abortController.signal);
        } catch (e, s) {
          if (e is! AbortException) {
            console.error('Error in worker: ${e.toString()}'.toJS);
            console.error('Original trace: $s'.toJS);
          }

          response = ErrorResponseUtils.wrapException(requestId, e);
        } finally {
          _handlingRequests.remove(requestId);
        }

        _send(response);
      },
      whenNotification: handleNotification,
      whenAbortRequest: (abort) {
        if (_handlingRequests.remove(abort.requestId) case final token?) {
          token.abort();
        }
      },
    );
  }

  /// Sends a request to the other end and expects a response of the
  /// [expectedType].
  ///
  /// The returned future completes with an error if the type doesn't match
  /// what's expected (for instance because an [ErrorResponse]) is sent instead.
  /// It also completes with an error if the channel gets closed in the
  /// meantime.
  ///
  /// If [abortTrigger] is given and completes before this request is completed,
  /// a request to cancel the request is sent to the remote.
  Future<Res> sendRequest<Res extends Response>(
    Request request,
    MessageType<Res> expectedType, {
    Future<void>? abortTrigger,
  }) async {
    if (_closed.isCompleted) {
      throw ChannelClosedException._();
    }

    final id = _nextRequestId++;
    final completer = _responses[id] = Completer.sync();

    _send(request..requestId = id);
    var hasResponse = false;

    if (abortTrigger != null) {
      abortTrigger.whenComplete(() {
        if (!hasResponse) {
          _send(newAbortRequest(requestId: id));
        }
      });
    }

    final response = await completer.future;
    hasResponse = true;
    if (response.type == expectedType.name) {
      return response as Res;
    } else {
      throw response.interpretAsError();
    }
  }

  void sendNotification(Notification notification) {
    _send(notification);
  }

  void handleNotification(Notification notification);

  Future<void> close([Object? error]) {
    _markClosed(error);
    return closed;
  }

  void _markClosed([Object? error]) {
    if (_closed.isCompleted) return;

    _port.postMessage(_disconnectMessage.toJS);
    _incomingMessagesSubscription?.cancel();
    _errorSubscription?.cancel();

    for (final response in _responses.values) {
      response.completeError(ChannelClosedException._(error));
    }
    _responses.clear();

    _closed.complete();
  }
}

/// An exception thrown when a request is sent over a closed channel to a
/// worker.
final class ChannelClosedException implements Exception {
  /// The original error causing the channel to be closed.
  final Object? closeReason;

  ChannelClosedException._([this.closeReason]);

  @override
  String toString() {
    return 'Channel to database worker is closed: $closeReason';
  }
}
