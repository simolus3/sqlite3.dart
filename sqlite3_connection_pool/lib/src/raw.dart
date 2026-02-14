import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';

import 'abort_exception.dart';
import 'ffi.g.dart';

final _poolFinalizer = NativeFinalizer(
  addresses.pkg_sqlite3_connection_pool_close.cast(),
);

final _requestFinalizer = NativeFinalizer(
  addresses.pkg_sqlite3_connection_pool_request_close.cast(),
);

@internal
final class RawSqliteConnectionPool implements Finalizable {
  var _requestCounter = 0;
  final Map<int, Completer<_PoolLease>> _outstandingRequests = {};

  final Pointer<ConnectionPool> _pool;
  final RawReceivePort _receivePort = RawReceivePort();
  final Object _detachToken = Object();

  int get _nativePort => _receivePort.sendPort.nativePort;

  RawSqliteConnectionPool._(this._pool) {
    _poolFinalizer.attach(this, _pool.cast(), detach: _detachToken);

    _receivePort.handler = (List<Object?> message) {
      final tag = message[0] as int;
      final isExclusive = message[1] as bool;
      final completer = _outstandingRequests.remove(tag);
      if (completer == null) {
        return;
      }

      completer.complete(
        isExclusive
            ? const _ExclusiveLease()
            : _SingleConnectionLease(Pointer.fromAddress(message[2] as int)),
      );
    };
  }

  (int, Completer<_PoolLease>) _createRequest() {
    final id = _requestCounter++;
    return (id, _outstandingRequests[id] = Completer());
  }

  (RawPoolRequest, Future<Pointer<Void>>) requestRead() {
    final (tag, completer) = _createRequest();
    final request = RawPoolRequest._(
      tag,
      this,
      pkg_sqlite3_connection_pool_obtain_read(_pool, tag, _nativePort),
    );

    return (
      request,
      completer.future.then((f) => (f as _SingleConnectionLease)._connection),
    );
  }

  (RawPoolRequest, Future<Pointer<Void>>) requestWrite() {
    final (tag, completer) = _createRequest();
    final request = RawPoolRequest._(
      tag,
      this,
      pkg_sqlite3_connection_pool_obtain_write(_pool, tag, _nativePort),
    );

    return (
      request,
      completer.future.then((f) => (f as _SingleConnectionLease)._connection),
    );
  }

  (RawPoolRequest, Future<void>) requestExclusive() {
    final (tag, completer) = _createRequest();
    final request = RawPoolRequest._(
      tag,
      this,
      pkg_sqlite3_connection_pool_obtain_exclusive(_pool, tag, _nativePort),
    );

    return (request, completer.future);
  }

  /// May only be called if the caller has an active exclusive request on this
  /// pool.
  ({Pointer<Void> writer, List<Pointer<Void>> readers}) queryConnections() {
    final amountOfReaders =
        pkg_sqlite3_connection_pool_query_read_connection_count(_pool);
    return using((alloc) {
      final writeConnectionPointer = alloc<Pointer<Void>>();
      final readConnectionPointers = alloc<Pointer<Void>>(amountOfReaders);

      pkg_sqlite3_connection_pool_query_connections(
        _pool,
        writeConnectionPointer,
        readConnectionPointers,
        amountOfReaders,
      );

      final readers = List.generate(
        amountOfReaders,
        (i) => readConnectionPointers[i],
      );
      return (writer: writeConnectionPointer.value, readers: readers);
    });
  }

  void close() {
    _poolFinalizer.detach(_detachToken);
    pkg_sqlite3_connection_pool_close(_pool);
    _receivePort.close();
  }

  static RawSqliteConnectionPool open(
    String name,
    PoolConnections Function() open,
  ) {
    (Object, StackTrace)? openException;

    final pool = using((alloc) {
      final encoded = utf8.encode(name);
      final namePtr = alloc<Uint8>(encoded.length);
      namePtr.asTypedList(encoded.length).setAll(0, encoded);

      final initializeCallable =
          NativeCallable<Pointer<InitializedPool> Function()>.isolateLocal(() {
            final initOptionsPtr = alloc<InitializedPool>();
            final initOptions = initOptionsPtr.ref;
            initOptions.functions
              ..sqlite3_close_v2 = Sqlite3.sqliteCloseV2
              ..dart_post_c_object = NativeApi.postCObject.cast();

            try {
              final PoolConnections(:readers, :writer) = open();

              initOptions.write = writer.leak().cast();
              initOptions.read_count = readers.length;
              initOptions.reads = alloc(readers.length);

              for (final (i, reader) in readers.indexed) {
                (initOptions.reads + i).value = reader.leak().cast();
              }
            } catch (e, s) {
              openException = (e, s);
              return nullptr;
            }

            return initOptionsPtr;
          });

      final connection = pkg_sqlite3_connection_pool_open(
        namePtr,
        encoded.length,
        initializeCallable.nativeFunction,
      );
      initializeCallable.close();
      return connection;
    });

    if (pool.address == 0) {
      if (openException case final exception?) {
        // Couldn't open because the callback threw an exception, rethrow that.
        Error.throwWithStackTrace(exception.$1, exception.$2);
      }

      // Unreachable, opening a pool can only fail due to the callback throwing.
      throw AssertionError();
    }

    return RawSqliteConnectionPool._(pool);
  }
}

final class PoolConnections {
  final Database writer;
  final List<Database> readers;

  PoolConnections(this.writer, this.readers);
}

@internal
final class RawPoolRequest implements Finalizable {
  final int _dartTag;
  final RawSqliteConnectionPool _pool;

  final Pointer<PoolRequest> _handle;
  final Object _detachToken = Object();

  RawPoolRequest._(this._dartTag, this._pool, this._handle) {
    _requestFinalizer.attach(this, _handle.cast(), detach: _detachToken);
  }

  bool get isCompleted => !_pool._outstandingRequests.containsKey(_dartTag);

  void close() {
    _requestFinalizer.detach(_detachToken);
    pkg_sqlite3_connection_pool_request_close(_handle);

    _pool._outstandingRequests
        .remove(_dartTag)
        ?.completeError(PoolAbortException());
  }
}

sealed class _PoolLease {
  const _PoolLease();
}

final class _SingleConnectionLease extends _PoolLease {
  /// The SQLite connection being leased.
  final Pointer<Void> _connection;

  _SingleConnectionLease(this._connection);
}

final class _ExclusiveLease extends _PoolLease {
  const _ExclusiveLease();
}
