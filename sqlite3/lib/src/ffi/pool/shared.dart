import 'dart:async';
import 'dart:isolate';

import 'package:meta/meta.dart';

import 'leased_database.dart';
import 'pool.dart';

/// A server sharing access to a [ConnectionPool] in a way that allows other
/// isolates to lease connections.
///
/// After creating a [PoolServer], use the [port] getter and
/// [PoolConnectPort.connect] on other isolates to obtain a [ConnectionPool]
/// again.
///
/// {@category native}
final class PoolServer {
  final ConnectionPool _pool;
  final ReceivePort _port = ReceivePort('PoolServer');

  final Map<SendPort, Set<_PendingRequest>> _pendingRequestsByClient = {};
  final Map<Capability, _PendingRequest> _pendingRequests = {};

  /// Constructs and starts a pool server giving leases to the provided
  /// [ConnectionPool].
  PoolServer(this._pool) {
    _port.listen((message) {
      switch (message) {
        case _AbortRequest(:final token):
          if (_pendingRequests[token] case final pending?) {
            if (!pending.granted) {
              pending.onAbort();
              _removeRequest(pending);
            }
            // If the request has already been granted, we can't abort it.
            // We would have sent a grant response in that case though, which
            // means that we'll get a _ReturnConnection back.
          }
        case _ReturnConnection(:final requestId):
          if (_pendingRequests[requestId] case final pending?) {
            pending.onReturned();
            _removeRequest(pending);
          }
        case _PoolCloseRequest(:final originalPort):
          if (_pendingRequestsByClient.remove(originalPort)
              case final pending?) {
            for (final request in pending) {
              request.onReturned();
              _removeRequest(request);
            }
          }
        case _RequestConnection():
          final abortCompleter = Completer<void>();
          final doneCompleter = Completer<void>();

          final request = _PendingRequest(
            client: message.originalPort,
            id: message.requestId,
            onReturned: doneCompleter.complete,
            onAbort: abortCompleter.complete,
          );
          _addRequest(request);

          Future<void> callback(LeasedDatabase db) async {
            request.granted = true;
            request.client.send(
              _GrantConnection(request.id, db.unsafeRawDatabase.handle.address),
            );
            await doneCompleter.future;
          }

          (message.writer
                  ? _pool.withWriter(callback, abort: abortCompleter.future)
                  : _pool.withReader(callback, abort: abortCompleter.future))
              // Abort exceptions are acknowledged on the other isolate.
              .onError<PoolAbortException>((e, s) {});
        case _RequestAllConnections():
          final doneCompleter = Completer<void>();
          final request = _PendingRequest(
            client: message.originalPort,
            id: message.requestId,
            onReturned: doneCompleter.complete,
            onAbort: () {},
          );
          _addRequest(request);

          Future<void> callback(
            List<LeasedDatabase> readers,
            LeasedDatabase writer,
          ) async {
            request.granted = true;

            request.client.send(
              _GrantAllConnection(
                request.id,
                writer.unsafeRawDatabase.handle.address,
                [
                  for (final reader in readers)
                    reader.unsafeRawDatabase.handle.address,
                ],
              ),
            );
            await doneCompleter.future;
          }

          _pool.withAllConnections(callback);
      }
    });
  }

  void _addRequest(_PendingRequest request) {
    _pendingRequests[request.id] = request;
    _pendingRequestsByClient.putIfAbsent(request.client, () => {}).add(request);
  }

  void _removeRequest(_PendingRequest request) {
    _pendingRequestsByClient[request.client]?.remove(request);
    _pendingRequests.remove(request.id);
  }

  /// The [PoolConnectPort] that can be passed to [connect] to obtain a
  /// [PoolImplementation] on another isolate.
  PoolConnectPort get port => PoolConnectPort._(_port.sendPort);

  Future<void> close() async {
    _port.close();
    for (final request in _pendingRequests.values.toList()) {
      request.onReturned();
      _removeRequest(request);
    }
  }
}

/// A [SendPort] that can be used to [connect] to a [PoolServer], giving access
/// to the [ConnectionPool].
///
/// Because this is a [SendPort], it can safely be sent across isolates.
extension type PoolConnectPort._(SendPort _port) {
  /// Connect to the [PoolServer] creating this port, returning a
  /// [ConnectionPool].
  ///
  /// When the connecting isolate is done with the pool, it should
  /// [ConnectionPool.close] the returned pool to free resources.
  ConnectionPool connect() {
    return RemotePool(_port);
  }
}

final class _PendingRequest {
  final SendPort client;
  final Capability id;
  final void Function() onReturned;
  final void Function() onAbort;
  var granted = false;

  _PendingRequest({
    required this.client,
    required this.id,
    required this.onReturned,
    required this.onAbort,
  });
}

@internal
final class RemotePool extends PoolImplementation {
  final SendPort _remotePool;
  final ReceivePort _receivePort = ReceivePort('RemotePool');
  late final SendPort ownCapability = _receivePort.sendPort;

  var _closing = false;
  final _pendingRequests = <Capability, Completer<Object>>{};
  final _outstandingCompletions = <Future<void>>{};

  RemotePool(this._remotePool) {
    Isolate.current.addOnExitListener(
      _remotePool,
      response: _PoolCloseRequest(ownCapability),
    );

    _receivePort.listen((message) {
      final id = switch (message) {
        _GrantConnection() => message.requestId,
        _GrantAllConnection() => message.requestId,
        _ => throw 'Unhandled message $message',
      };

      if (_pendingRequests.remove(id) case final pending?) {
        pending.complete(message);
      } else {
        // Return the lock to avoid a deadlock.
        _remotePool.send(_ReturnConnection(id));
      }
    });
  }

  @override
  Future<void> close() async {
    _closing = true;

    while (_outstandingCompletions.isNotEmpty) {
      final currentlyActive = _outstandingCompletions.toList();
      await Future.wait(currentlyActive);
    }

    _receivePort.close();
    _remotePool.send(_PoolCloseRequest(ownCapability));
    Isolate.current.removeOnExitListener(_remotePool);
  }

  void _checkNotClosed() {
    if (_closing) {
      throw StateError('RemotePool is closed');
    }
  }

  @override
  Future<T> withAllConnections<T>(
    FutureOr<T> Function(List<LeasedDatabase> readers, LeasedDatabase writer)
    callback,
  ) async {
    _checkNotClosed();

    final completer = Completer<Object>();
    final requestId = Capability();
    _pendingRequests[requestId] = completer;
    _remotePool.send(_RequestAllConnections(ownCapability, requestId));

    final completion = Completer();
    _outstandingCompletions.add(completion.future);
    final granted = (await completer.future) as _GrantAllConnection;
    final writer = pointerToDatabase(granted.writer);
    final readers = [
      for (final address in granted.readers) pointerToDatabase(address),
    ];

    try {
      return await wrapWithLease(writer, (writer) async {
        return wrapWithLeases(readers, (readers) => callback(readers, writer));
      });
    } finally {
      _remotePool.send(_ReturnConnection(requestId));
      _outstandingCompletions.remove(completion.future);
      completion.complete();
    }
  }

  Future<T> _withConnection<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    required bool writer,
    Future<void>? abort,
  }) async {
    _checkNotClosed();

    final started = Completer<Object>();
    final done = Completer();
    final requestId = Capability();
    _pendingRequests[requestId] = started;

    if (abort != null) {
      abort.whenComplete(() {
        if (!started.isCompleted) {
          _pendingRequests.remove(requestId);
          _remotePool.send(_AbortRequest(requestId));
          started.completeError(const PoolAbortException());
          done.complete();
        }
      });
    }

    _outstandingCompletions.add(done.future);
    _remotePool.send(_RequestConnection(writer, ownCapability, requestId));

    final granted = (await started.future) as _GrantConnection;
    final database = pointerToDatabase(granted.connectionPointer);
    try {
      return await wrapWithLease(database, callback);
    } finally {
      _remotePool.send(_ReturnConnection(requestId));
      _outstandingCompletions.remove(done.future);
      done.complete();
    }
  }

  @override
  Future<T> withReader<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    Future<void>? abort,
  }) {
    return _withConnection(callback, writer: false, abort: abort);
  }

  @override
  Future<T> withWriter<T>(
    FutureOr<T> Function(LeasedDatabase db) callback, {
    Future<void>? abort,
  }) {
    return _withConnection(callback, writer: true, abort: abort);
  }
}

final class _RequestConnection {
  final bool writer;
  final SendPort originalPort;
  final Capability requestId;

  _RequestConnection(this.writer, this.originalPort, this.requestId);
}

final class _RequestAllConnections {
  final SendPort originalPort;
  final Capability requestId;

  _RequestAllConnections(this.originalPort, this.requestId);
}

/// Abort requesting a connection.
///
/// If the client still receives a [_GrantConnection] for a request it
/// previously aborted, it must respond with a [_ReturnConnection].
final class _AbortRequest {
  final Capability token;

  _AbortRequest(this.token);
}

/// Disconnect from a pool, automatically returning locks currently held by the
/// client. Note that this is an extension type on [SendPort] because isolate
/// exit messages are restricted - and we want to send a close request when the
/// isolate exists to return the connection.
extension type _PoolCloseRequest(SendPort originalPort) {}

/// Notify a client that a connection has been granted. The client must send a
/// [_ReturnConnection] message when it's done with the connection.
final class _GrantConnection {
  final Capability requestId;
  final int connectionPointer;

  _GrantConnection(this.requestId, this.connectionPointer);
}

/// Notify a client that all connections have been granted (for a
/// [ConnectionPool.withAllConnections] call).
///
/// The client must send a [_ReturnConnection] message when it's done with the
/// connections.
final class _GrantAllConnection {
  final Capability requestId;
  final int writer;
  final List<int> readers;

  _GrantAllConnection(this.requestId, this.writer, this.readers);
}

/// Returns a database lease.
final class _ReturnConnection {
  final Capability requestId;

  _ReturnConnection(this.requestId);
}
