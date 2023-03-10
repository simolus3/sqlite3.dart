import 'dart:convert';

import '../constants.dart';
import '../database.dart';
import '../exception.dart';
import '../statement.dart';
import '../result_set.dart';
import '../functions.dart';
import 'bindings.dart';
import 'exception.dart';
import 'finalizer.dart';
import 'statement.dart';

/// Contains the state of a database needed for finalization.
///
/// This is extracted into separate object so that it can be used as a
/// finalization token. It will get disposed when the main database is no longer
/// reachable without being closed.
class FinalizableDatabase extends FinalizablePart {
  final RawSqliteBindings bindings;
  final RawSqliteDatabase database;

  final List<FinalizableStatement> _statements = [];

  FinalizableDatabase(this.bindings, this.database);

  @override
  void dispose() {
    for (final stmt in _statements) {
      stmt.dispose();
    }

    final code = database.sqlite3_close_v2();
    SqliteException? exception;
    if (code != SqlError.SQLITE_OK) {
      exception = createExceptionRaw(bindings, database, code,
          operation: 'closing database');
    }

    database.deallocateAdditionalMemory();

    if (exception != null) {
      throw exception;
    }
  }
}

class DatabaseImplementation implements CommonDatabase {
  final RawSqliteBindings bindings;
  final RawSqliteDatabase database;

  final FinalizableDatabase finalizable;

  var _isClosed = false;

  @override
  int userVersion = 0;

  DatabaseImplementation(this.bindings, this.database)
      : finalizable = FinalizableDatabase(bindings, database) {
    disposeFinalizer.attach(this, finalizable, detach: this);
  }

  void handleFinalized(StatementImplementation stmt) {
    if (!_isClosed) {
      finalizable._statements.remove(stmt.finalizable);
    }
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('This database has already been closed');
    }
  }

  @override
  void createAggregateFunction<V>(
      {required String functionName,
      required AggregateFunction<V> function,
      AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
      bool deterministic = false,
      bool directOnly = true}) {
    // TODO: implement createAggregateFunction
  }

  @override
  void createCollation(
      {required String name, required CollatingFunction function}) {
    // TODO: implement createCollation
  }

  @override
  void createFunction(
      {required String functionName,
      required ScalarFunction function,
      AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
      bool deterministic = false,
      bool directOnly = true}) {
    // TODO: implement createFunction
  }

  @override
  void dispose() {
    if (_isClosed) return;

    disposeFinalizer.detach(this);
    _isClosed = true;
    // TODO updates.close()
    finalizable.dispose();
  }

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    if (parameters.isEmpty) {
      // No parameters? Use sqlite3_exec since that can run multiple statements
      // at once.
      _ensureOpen();

      final result = database.sqlite3_exec(sql);
      if (result != SqlError.SQLITE_OK) {
        throwException(
          this,
          result,
          operation: 'executing',
          previousStatement: sql,
          statementArgs: parameters,
        );
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
  int getUpdatedRows() => database.sqlite3_changes();

  @override
  int get lastInsertRowId => database.sqlite3_last_insert_rowid();

  StatementImplementation createStatement(
      String sql, RawSqliteStatement statement) {
    return StatementImplementation(sql, this, statement);
  }

  List<StatementImplementation> _prepareInternal(String sql,
      {bool persistent = false,
      bool vtab = true,
      int? maxStatements,
      bool checkNoTail = false}) {
    _ensureOpen();

    final bytes = utf8.encode(sql);
    final compiler = database.newCompiler(bytes);

    var prepFlags = 0;
    if (persistent) {
      prepFlags |= SqlPrepareFlag.SQLITE_PREPARE_PERSISTENT;
    }
    if (!vtab) {
      prepFlags |= SqlPrepareFlag.SQLITE_PREPARE_NO_VTAB;
    }

    final createdStatements = <StatementImplementation>[];
    var offset = 0;

    void freeIntermediateResults() {
      compiler.close();

      for (final stmt in createdStatements) {
        stmt.dispose();
      }
    }

    while (offset < bytes.length) {
      final result =
          compiler.sqlite3_prepare(offset, bytes.length - offset, prepFlags);

      if (result.resultCode != SqlError.SQLITE_OK) {
        freeIntermediateResults();
        throwException(this, result.resultCode,
            operation: 'preparing statement', previousStatement: sql);
      }

      final endOffset = compiler.endOffset;

      // prepare can return a null pointer with SQLITE_OK if only whitespace
      // or comments were parsed. That's fine, just skip over it then.
      final stmt = result.result;
      if (stmt != null) {
        createdStatements
            .add(createStatement(sql.substring(offset, endOffset), stmt));
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
        final result =
            compiler.sqlite3_prepare(offset, bytes.length - offset, prepFlags);
        offset = compiler.endOffset;

        final stmt = result.result;

        if (stmt != null) {
          // Had an unexpected trailing statement -> throw!
          createdStatements.add(createStatement('', stmt));
          freeIntermediateResults();
          throw ArgumentError.value(
              sql, 'sql', 'Had an unexpected trailing statement.');
        } else if (result.resultCode != SqlError.SQLITE_OK) {
          // Invalid content that's not just a whitespace or a comment.
          freeIntermediateResults();
          throw ArgumentError.value(
              sql, 'sql', 'Has trailing data after the first sql statement:');
        }
      }
    }

    compiler.close();

    for (final created in createdStatements) {
      finalizable._statements.add(created.finalizable);
    }

    return createdStatements;
  }

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

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    final stmt = prepare(sql);
    try {
      return stmt.select(parameters);
    } finally {
      stmt.dispose();
    }
  }

  @override
  // TODO: implement updates
  Stream<SqliteUpdate> get updates => throw UnimplementedError();
}
