import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../common/constants.dart';
import '../common/database.dart';
import '../common/exception.dart';
import '../common/functions.dart';
import '../common/impl/finalizer.dart';
import '../common/impl/utils.dart';
import '../common/statement.dart';
import 'bindings.dart';
import 'exception.dart';
import 'statement.dart';

/// Extracted parts of a wasm database needed for disposing it natively.
///
/// This is extracted from the main class so that this can be used as a
/// finalization token.
class _FinalizableDatabase extends FinalizablePart {
  final WasmBindings bindings;
  final Pointer db;
  final List<WasmFinalizableStatement> _statements = [];

  _FinalizableDatabase(this.bindings, this.db);

  @override
  void dispose() {
    for (final stmt in _statements) {
      stmt.dispose();
    }

    final code = bindings.sqlite3_close_v2(db);
    final exception = code != SqlError.SQLITE_OK
        ? createExceptionRaw(bindings, db, code)
        : null;

    // We don't need to deallocate the db pointer, sqlite3 takes care of that.
    if (exception != null) {
      throw exception;
    }
  }
}

@internal
class WasmDatabase extends CommonDatabase {
  final WasmBindings bindings;
  final Pointer db;

  final _FinalizableDatabase _finalizable;
  final Finalizer<FinalizablePart> _finalizer = disposeFinalizer;

  bool _isClosed = false;
  final int _databaseId;
  final List<MultiStreamController<SqliteUpdate>> _updateListeners = [];

  WasmDatabase(this.bindings, this.db)
      : _finalizable = _FinalizableDatabase(bindings, db),
        _databaseId = bindings.lastDatabaseId++ {
    _finalizer.attach(this, _finalizable, detach: this);
  }

  SqliteException createException(int returnCode, [String? previousStatement]) {
    return createExceptionRaw(bindings, db, returnCode, previousStatement);
  }

  Never throwException(int returnCode, [String? previousStatement]) {
    throw createException(returnCode, previousStatement);
  }

  @override
  void createAggregateFunction<V>(
      {required String functionName,
      required AggregateFunction<V> function,
      AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
      bool deterministic = false,
      bool directOnly = true}) {
    final id = bindings.functions.register(function);
    final name = _functionName(functionName);

    final add = function is WindowFunction<V>
        ? bindings.create_window_function
        : bindings.create_aggregate_function;

    final result = add(
      db,
      name,
      argumentCount.allowedArgs,
      eTextRep(deterministic, directOnly),
      id,
    );
    bindings.free(name);

    if (result != SqlError.SQLITE_OK) {
      throwException(result);
    }
  }

  @override
  void createCollation(
      {required String name, required CollatingFunction function}) {
    throw UnimplementedError();
  }

  @override
  void createFunction(
      {required String functionName,
      required ScalarFunction function,
      AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
      bool deterministic = false,
      bool directOnly = true}) {
    final id = bindings.functions.register(function);
    final name = _functionName(functionName);

    final result = bindings.create_scalar_function(
      db,
      name,
      argumentCount.allowedArgs,
      eTextRep(deterministic, directOnly),
      id,
    );
    bindings.free(name);

    if (result != SqlError.SQLITE_OK) {
      throwException(result);
    }
  }

  Pointer _functionName(String functionName) {
    final functionNameBytes = utf8.encode(functionName);

    if (functionNameBytes.length > 255) {
      throw ArgumentError.value(functionName, 'functionName',
          'Must not exceed 255 bytes when utf-8 encoded');
    }

    return bindings.allocateBytes(functionNameBytes, additionalLength: 1);
  }

  @override
  void dispose() {
    if (_isClosed) return;

    _isClosed = true;
    _finalizer.detach(this);
    _finalizable.dispose();

    for (final listener in _updateListeners) {
      listener.close();
    }
  }

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    if (parameters.isEmpty) {
      // Use sqlite3_exec since that can run multiple statements at once.
      _ensureOpen();

      final sqlPtr = bindings.allocateZeroTerminated(sql);
      final errorOut = bindings.malloc(WasmBindings.pointerSize);

      final result = bindings.sqlite3_exec(db, sqlPtr, 0, 0, errorOut);
      bindings.free(sqlPtr);

      final errorPtr = bindings.int32ValueOfPointer(errorOut);
      bindings.free(errorOut);

      String? errorMessage;
      if (errorPtr != 0) {
        errorMessage = bindings.memory.readString(errorPtr);

        // The message was allocated from sqlite3, we need to free it.
        bindings.free(errorPtr);
      }

      if (result != SqlError.SQLITE_OK) {
        throw SqliteException(
            result, errorMessage ?? 'unknown error', null, sql);
      }
    } else {
      final stmt = prepare(sql, checkNoTail: true);

      try {
        stmt.execute(parameters);
      } finally {
        stmt.dispose();
      }
    }
  }

  @override
  int getUpdatedRows() => bindings.sqlite3_changed(db);

  @override
  int get lastInsertRowId => bindings.sqlite3_last_insert_rowid(db);

  @override
  CommonPreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true, bool checkNoTail = false}) {
    final stmts = _prepareInternal(
      sql,
      persistent: persistent,
      vtab: vtab,
      maxStatements: 1,
      checkNoTail: checkNoTail,
    );

    if (stmts.isEmpty) {
      // Can happen without a syntax error if we're only given whitespace or
      // comments.
      throw ArgumentError.value(sql, 'sql', 'Must contain an SQL statement.');
    }

    return stmts.first;
  }

  @override
  List<CommonPreparedStatement> prepareMultiple(String sql,
      {bool persistent = false, bool vtab = true}) {
    return _prepareInternal(sql, persistent: persistent, vtab: vtab);
  }

  List<WasmStatement> _prepareInternal(String sql,
      {bool persistent = false,
      bool vtab = true,
      int? maxStatements,
      bool checkNoTail = false}) {
    _ensureOpen();

    final stmtOut = bindings.malloc(WasmBindings.pointerSize);
    final pzTail = bindings.malloc(WasmBindings.pointerSize);

    final bytes = utf8.encode(sql);
    final sqlPtr = bindings.allocateBytes(bytes);

    var prepFlags = 0;
    if (persistent) {
      prepFlags |= SqlPrepareFlag.SQLITE_PREPARE_PERSISTENT;
    }
    if (!vtab) {
      prepFlags |= SqlPrepareFlag.SQLITE_PREPARE_NO_VTAB;
    }

    final createdStatements = <WasmStatement>[];
    var offset = 0;

    void freeIntermediateResults() {
      bindings
        ..free(stmtOut)
        ..free(sqlPtr)
        ..free(pzTail);

      for (final stmt in createdStatements) {
        bindings.sqlite3_finalize(stmt.statement);
      }
    }

    int prepare() {
      return bindings.sqlite3_prepare_v3(db, sqlPtr + offset,
          bytes.length - offset, prepFlags, stmtOut, pzTail);
    }

    while (offset < bytes.length) {
      final resultCode = prepare();

      if (resultCode != SqlError.SQLITE_OK) {
        freeIntermediateResults();
        throwException(resultCode, sql);
      }

      final stmtPtr = bindings.int32ValueOfPointer(stmtOut);
      final endOffset = bindings.int32ValueOfPointer(pzTail) - sqlPtr;

      // prepare can return a null pointer with SQLITE_OK if only whitespace
      // or comments were parsed. That's fine, just skip over it then.
      if (stmtPtr != 0) {
        final sqlForStatement = utf8.decoder.convert(bytes, offset, endOffset);
        final stmt = WasmStatement(this, stmtPtr, sqlForStatement);

        createdStatements.add(stmt);
      }

      offset = endOffset;

      if (createdStatements.length == maxStatements) {
        break;
      }
    }

    if (checkNoTail) {
      // Issue another prepare call at the current offset to account for
      // potential whitespace.
      while (offset < bytes.length) {
        final resultCode = prepare();
        offset = bindings.int32ValueOfPointer(pzTail) - sqlPtr;

        final stmtPtr = bindings.int32ValueOfPointer(stmtOut);

        if (stmtPtr != 0) {
          // Had an unexpected trailing statement -> throw!
          createdStatements.add(WasmStatement(this, stmtPtr, ''));
          freeIntermediateResults();
          throw ArgumentError.value(
              sql, 'sql', 'Had an unexpected trailing statement.');
        } else if (resultCode != SqlError.SQLITE_OK) {
          // Invalid content that's not just a whitespace or a comment.
          freeIntermediateResults();
          throw ArgumentError.value(
              sql, 'sql', 'Has trailing data after the first sql statement:');
        }
      }
    }

    bindings
      ..free(stmtOut)
      ..free(sqlPtr)
      ..free(pzTail);

    for (final created in createdStatements) {
      _finalizable._statements.add(created.finalizable);
    }
    return createdStatements;
  }

  @override
  Stream<SqliteUpdate> get updates {
    return Stream.multi(
      (listener) {
        StreamSubscription<SqliteUpdate>? subscription;

        void resume() {
          if (_updateListeners.isEmpty) {
            // Start listening for updates.
            bindings.dart_sqlite3_updates(db, _databaseId);
          }
          _updateListeners.add(listener);
          subscription?.resume();
        }

        void pause() {
          _updateListeners.remove(listener);

          if (_updateListeners.isEmpty) {
            // Disable listening to updates for this database.
            bindings.dart_sqlite3_updates(db, -1);
          }
        }

        void start() {
          resume();

          subscription = bindings.allUpdates
              .where((e) => e.databaseId == _databaseId)
              .map((e) => e.update)
              .listen(listener.addSync, onError: listener.addErrorSync);
        }

        void stop() {
          pause();
          subscription?.cancel();
        }

        start();
        listener
          ..onPause = pause
          ..onResume = resume
          ..onCancel = stop;
      },
      isBroadcast: true,
    );
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('This database has already been closed');
    }
  }

  void handleFinalized(WasmStatement stmt) {
    if (!_isClosed) {
      _finalizable._statements.remove(stmt.finalizable);
    }
  }
}
