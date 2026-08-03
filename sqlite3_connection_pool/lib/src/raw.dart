import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

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

  void sendCustomUpdateNotification(List<String> updatedTables) {
    using((alloc) {
      final rawUpdates = alloc<Pointer<Char>>(updatedTables.length);
      for (final (i, update) in updatedTables.indexed) {
        final ptr = update.toNativeUtf8(allocator: alloc).cast<Char>();
        rawUpdates[i] = ptr;
      }

      pkg_sqlite3_connection_pool_notify_updates_custom(
        _pool,
        rawUpdates,
        updatedTables.length,
      );
    });
  }

  void addReaders(List<Database> connections) {
    using((alloc) {
      final readConnectionPointers = alloc<Pointer<Void>>(connections.length);

      for (final (i, reader) in connections.indexed) {
        (readConnectionPointers + i).value = reader.leak().cast();
      }

      pkg_sqlite3_connection_pool_add_readers(
        _pool,
        connections.length,
        readConnectionPointers,
      );
    });
  }

  (int, Completer<_PoolLease>) _createRequest() {
    final id = _requestCounter++;
    return (id, _outstandingRequests[id] = Completer());
  }

  (RawPoolRequest, Future<PoolConnectionRef>) requestSingleConnection(
    bool read,
  ) {
    final (tag, completer) = _createRequest();
    final request = RawPoolRequest._(
      tag,
      this,
      pkg_sqlite3_connection_pool_obtain_single(
        _pool,
        tag,
        _nativePort,
        read ? 1 : 0,
      ),
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
              ..sqlite3_get_autocommit = libsqlite3
                  .addresses
                  .sqlite3_get_autocommit
                  .cast()
              ..sqlite3_finalize = libsqlite3.addresses.sqlite3_finalize.cast()
              ..sqlite3_close_v2 = libsqlite3.addresses.sqlite3_close_v2.cast()
              ..dart_post_c_object = NativeApi.postCObject.cast();

            try {
              final PoolConnections(
                :readers,
                :writer,
                :preparedStatementCacheSize,
                :enableNativeUpdateHooks,
              ) = open();

              initOptions.write = writer.leak().cast();
              initOptions.read_count = readers.length;
              initOptions.reads = alloc(readers.length);
              initOptions.prepared_statement_cache_size =
                  preparedStatementCacheSize;
              initOptions.enable_update_hooks = enableNativeUpdateHooks ? 1 : 0;

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
      if (openException case (final exception, final trace)?) {
        // Couldn't open because the callback threw an exception, rethrow that.
        Error.throwWithStackTrace(exception, trace);
      }

      // Unreachable, opening a pool can only fail due to the callback throwing.
      throw AssertionError();
    }

    return RawSqliteConnectionPool._(pool);
  }
}

/// A write and a collection of read connections to put into a connection pool.
///
/// All connections ([readers] and [writer]) should point to the same database
/// file to form a valid pool. Additionally, connections should use the
/// [WAL](https://sqlite.org/wal.html) journal mode to support parallel reads
/// and writes.
final class PoolConnections {
  /// The connection used for writes to the database.
  final Database writer;

  /// Connections used to serve database reads.
  ///
  /// This can be empty, in which case reads on the pool can also use the
  /// [writer] connection as a fallback.
  final List<Database> readers;

  /// If set to a positive value, creates a cache of prepared statements for
  /// each connection.
  ///
  /// The cache is a LRU map with the indicated size.
  final int preparedStatementCacheSize;

  /// Whether native update notifications backed by `sqlite3_update_hook` should
  /// be enabled.
  final bool enableNativeUpdateHooks;

  PoolConnections(
    this.writer,
    this.readers, {
    this.preparedStatementCacheSize = 0,
    this.enableNativeUpdateHooks = true,
  }) : assert(preparedStatementCacheSize >= 0);
}

extension type PoolConnectionRef(
  /// The pool connection, used to manage cached prepared statements.
  Pointer<PoolConnection> connection
) {
  /// The `sqlite3*` connection pointer.
  Pointer<Void> get rawDatabase => connection.ref.raw;

  Pointer<Void> lookupCachedStatement(Uint8List sql) {
    return pkg_sqlite3_connection_pool_stmt_cache_get(
      connection,
      sql.address,
      sql.length,
    );
  }

  bool putCachedStatement(Uint8List sql, Pointer<Void> statement) {
    return pkg_sqlite3_connection_pool_stmt_cache_put(
          connection,
          sql.address,
          sql.length,
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

  void notifyUpdates() {
    pkg_sqlite3_connection_pool_notify_updates(_handle);
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
