import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/unstable/ffi_bindings.dart' as libsqlite3;

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

      _PoolLease parsed;
      if (isExclusive) {
        parsed = const _ExclusiveLease();
      } else {
        final poolConnection = Pointer<PoolConnection>.fromAddress(
          message[2] as int,
        );
        parsed = _SingleConnectionLease(PoolConnectionRef(poolConnection));
      }

      completer.complete(parsed);
    };
  }

  (int, Completer<_PoolLease>) _createRequest() {
    final id = _requestCounter++;
    return (id, _outstandingRequests[id] = Completer());
  }

  (RawPoolRequest, Future<PoolConnectionRef>) requestRead() {
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

  (RawPoolRequest, Future<PoolConnectionRef>) requestWrite() {
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
  ({PoolConnectionRef writer, List<PoolConnectionRef> readers})
  queryConnections() {
    final amountOfReaders =
        pkg_sqlite3_connection_pool_query_read_connection_count(_pool);
    return using((alloc) {
      final writeConnectionPointer = alloc<Pointer<PoolConnection>>();
      final readConnectionPointers = alloc<Pointer<PoolConnection>>(
        amountOfReaders,
      );

      pkg_sqlite3_connection_pool_query_connections(
        _pool,
        writeConnectionPointer,
        readConnectionPointers,
        amountOfReaders,
      );

      final readers = List.generate(
        amountOfReaders,
        (i) => PoolConnectionRef(readConnectionPointers[i]),
      );

      return (
        writer: PoolConnectionRef(writeConnectionPointer.value),
        readers: readers,
      );
    });
  }

  void addUpdateListener(SendPort port) {
    pkg_sqlite3_connection_pool_update_listener(_pool, 1, port.nativePort);
  }

  void removeUpdateListener(SendPort port) {
    pkg_sqlite3_connection_pool_update_listener(_pool, 0, port.nativePort);
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
              ..sqlite3_update_hook = libsqlite3.addresses.sqlite3_update_hook
                  .cast()
              ..sqlite3_rollback_hook = libsqlite3
                  .addresses
                  .sqlite3_rollback_hook
                  .cast()
              ..sqlite3_commit_hook = libsqlite3.addresses.sqlite3_commit_hook
                  .cast()
              ..sqlite3_finalize = libsqlite3.addresses.sqlite3_finalize.cast()
              ..sqlite3_close_v2 = libsqlite3.addresses.sqlite3_close_v2.cast()
              ..dart_post_c_object = NativeApi.postCObject.cast();

            try {
              final PoolConnections(
                :readers,
                :writer,
                :preparedStatementCacheSize,
              ) = open();

              initOptions.write = writer.leak().cast();
              initOptions.read_count = readers.length;
              initOptions.reads = alloc(readers.length);
              initOptions.prepared_statement_cache_size =
                  preparedStatementCacheSize;

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

/// A write and a collection of read connections to put into a connection pool.
final class PoolConnections {
  final Database writer;
  final List<Database> readers;

  /// If set to a positive value, creates a cache of prepared statements for
  /// each connection.
  ///
  /// The cache is a LRU map with the indicated size.
  final int preparedStatementCacheSize;

  PoolConnections(
    this.writer,
    this.readers, {
    this.preparedStatementCacheSize = 0,
  }) : assert(preparedStatementCacheSize >= 0);
}

extension type PoolConnectionRef(
  /// The pool connection, used to manage cached prepared statements.
  Pointer<PoolConnection>
  connection
) {
  /// The `sqlite3*` connection pointer.
  Pointer<Void> get rawDatabase => connection.ref.raw;

  Pointer<Void> lookupCachedStatement(String sql) {
    final encoded = utf8.encode(sql);
    return pkg_sqlite3_connection_pool_stmt_cache_get(
      connection,
      encoded.address,
      encoded.length,
    );
  }

  bool putCachedStatement(String sql, Pointer<Void> statement) {
    final encoded = utf8.encode(sql);
    return pkg_sqlite3_connection_pool_stmt_cache_put(
          connection,
          encoded.address,
          encoded.length,
          statement,
          libsqlite3.addresses.sqlite3_finalize.cast(),
        ) !=
        0;
  }
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
  final PoolConnectionRef _connection;

  _SingleConnectionLease(this._connection);
}

final class _ExclusiveLease extends _PoolLease {
  const _ExclusiveLease();
}
