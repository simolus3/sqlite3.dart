import '../constants.dart';
import '../result_set.dart';
import '../statement.dart';
import 'bindings.dart';
import 'database.dart';
import 'exception.dart';
import 'finalizer.dart';
import 'utils.dart';

final class FinalizableStatement extends FinalizablePart {
  final RawSqliteStatement statement;

  bool _inResetState = true;
  bool _closed = false;

  FinalizableStatement(this.statement);

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;
      _reset();
      statement.sqlite3_finalize();
    }
  }

  void _reset() {
    if (!_inResetState) {
      statement.sqlite3_reset();
      _inResetState = true;
    }

    statement.deallocateArguments();
  }
}

base class StatementImplementation implements CommonPreparedStatement {
  final RawSqliteStatement statement;
  final DatabaseImplementation database;
  final FinalizableStatement finalizable;

  @override
  final String sql;
  List<Object?>? _latestArguments;

  _ActiveCursorIterator? _currentCursor;

  StatementImplementation(this.sql, this.database, this.statement)
      : finalizable = FinalizableStatement(statement);

  List<String> get _columnNames {
    final columnCount = statement.sqlite3_column_count();

    return [
      for (var i = 0; i < columnCount; i++) statement.sqlite3_column_name(i)
    ];
  }

  List<String?>? get _tableNames {
    if (!statement.supportsReadingTableNameForColumn) {
      return null;
    }

    final columnCount = statement.sqlite3_column_count();
    return List.generate(columnCount, statement.sqlite3_column_table_name);
  }

  void _ensureNotFinalized() {
    if (finalizable._closed) {
      throw StateError('Tried to operate on a released prepared statement');
    }
  }

  void _ensureMatchingParameters(List<Object?>? parameters) {
    final length = parameters?.length ?? 0;
    final count = parameterCount;

    if (length != count) {
      throw ArgumentError.value(
          parameters, 'parameters', 'Expected $count parameters, got $length');
    }
  }

  int _step() => statement.sqlite3_step();

  void _reset() {
    finalizable._reset();
    _currentCursor = null;
  }

  void _execute() {
    int result;

    finalizable._inResetState = false;
    // Users should be able to execute statements returning rows, so we should
    // call _step() to skip past rows.
    do {
      result = _step();
    } while (result == SqlError.SQLITE_ROW);

    if (result != SqlError.SQLITE_OK && result != SqlError.SQLITE_DONE) {
      throwException(
        database,
        result,
        operation: 'executing statement',
        previousStatement: sql,
        statementArgs: _latestArguments,
      );
    }
  }

  ResultSet _selectResults() {
    final names = _columnNames;
    final tableNames = _tableNames;
    final columnCount = names.length;
    final rows = <List<Object?>>[];
    finalizable._inResetState = false;

    int resultCode;
    while ((resultCode = _step()) == SqlError.SQLITE_ROW) {
      rows.add(<Object?>[for (var i = 0; i < columnCount; i++) _readValue(i)]);
    }

    if (resultCode != SqlError.SQLITE_OK &&
        resultCode != SqlError.SQLITE_DONE) {
      throwException(
        database,
        resultCode,
        operation: 'selecting from statement',
        previousStatement: sql,
        statementArgs: _latestArguments,
      );
    }

    return ResultSet(names, tableNames, rows);
  }

  Object? _readValue(int index) {
    final type = statement.sqlite3_column_type(index);
    switch (type) {
      case SqlType.SQLITE_INTEGER:
        const hasNativeInts = !identical(0.0, 0);

        if (hasNativeInts) {
          return statement.sqlite3_column_int64(index);
        } else {
          // Wrap in BigInt if needed
          return statement.sqlite3_column_int64OrBigInt(index);
        }

      case SqlType.SQLITE_FLOAT:
        return statement.sqlite3_column_double(index);
      case SqlType.SQLITE_TEXT:
        return statement.sqlite3_column_text(index);
      case SqlType.SQLITE_BLOB:
        return statement.sqlite3_column_bytes(index);
      case SqlType.SQLITE_NULL:
      default:
        return null;
    }
  }

  void _bindParams(List<Object?>? params) {
    _ensureMatchingParameters(params);
    if (params == null || params.isEmpty) return;

    // variables in sqlite are 1-indexed
    for (var i = 1; i <= params.length; i++) {
      final Object? param = params[i - 1];

      _bindParam(param, i);
    }

    _latestArguments = params;
  }

  void _bindMapParams(Map<String, Object?> params) {
    final expectedLength = parameterCount;
    final paramsAsList = List<Object?>.filled(expectedLength, null);

    if (params.isEmpty) {
      if (expectedLength != 0) {
        throw ArgumentError.value(params, 'params',
            'Expected $expectedLength parameters, but none were set.');
      }
      return;
    }

    for (final key in params.keys) {
      final Object? param = params[key];
      final i = statement.sqlite3_bind_parameter_index(key);

      // SQL parameters are 1-indexed, so 0 indicates that no parameter with
      // that name was found.
      if (i == 0) {
        throw ArgumentError.value(params, 'params',
            'This statement contains no parameter named `$key`');
      }
      _bindParam(param, i);
      paramsAsList[i - 1] = param;
    }

    // If we reached this point. All parameters from [params] were bound. Check
    // if the statement contains no additional parameters.
    if (expectedLength != params.length) {
      throw ArgumentError.value(
          params, 'params', 'Expected $expectedLength parameters');
    }

    _latestArguments = paramsAsList;
  }

  void _bindParam(Object? param, int i) {
    // TODO: Replace with switch expression after https://github.com/dart-lang/sdk/issues/52234
    switch (param) {
      case null:
        statement.sqlite3_bind_null(i);
      case int():
        statement.sqlite3_bind_int64(i, param);
      case BigInt():
        statement.sqlite3_bind_int64BigInt(i, param.checkRange);
      case bool():
        statement.sqlite3_bind_int64(i, param ? 1 : 0);
      case double():
        statement.sqlite3_bind_double(i, param);
      case String():
        statement.sqlite3_bind_text(i, param);
      case List<int>():
        statement.sqlite3_bind_blob64(i, param);
      default:
        throw ArgumentError.value(
          param,
          'params[$i]',
          'Allowed parameters must either be null or bool, int, num, String or '
              'List<int>.',
        );
    }
  }

  @override
  void dispose() {
    if (!finalizable._closed) {
      disposeFinalizer.detach(this);
      finalizable.dispose();

      database.handleFinalized(this);
    }
  }

  @override
  void execute([List<Object?> parameters = const <Object>[]]) {
    _ensureNotFinalized();

    _reset();
    _bindParams(parameters);
    _execute();
  }

  @override
  void executeMap(Map<String, Object?> parameters) {
    _ensureNotFinalized();

    _reset();
    _bindMapParams(parameters);

    _execute();
  }

  @override
  int get parameterCount => statement.sqlite3_bind_parameter_count();

  @override
  ResultSet select([List<Object?> parameters = const <Object>[]]) {
    _ensureNotFinalized();

    _reset();
    _bindParams(parameters);

    return _selectResults();
  }

  @override
  IteratingCursor selectCursor([List<Object?> parameters = const <Object>[]]) {
    _ensureNotFinalized();

    _reset();
    _bindParams(parameters);

    final names = _columnNames;
    final tableNames = _tableNames;
    return _currentCursor = _ActiveCursorIterator(this, names, tableNames);
  }

  @override
  ResultSet selectMap(Map<String, Object?> parameters) {
    _ensureNotFinalized();

    _reset();
    _bindMapParams(parameters);

    return _selectResults();
  }
}

class _ActiveCursorIterator extends IteratingCursor {
  final StatementImplementation statement;
  final int columnCount;

  @override
  late Row current;

  _ActiveCursorIterator(
    this.statement,
    List<String> columnNames,
    List<String?>? tableNames,
  )   : columnCount = columnNames.length,
        super(columnNames, tableNames) {
    statement.finalizable._inResetState = false;
  }

  @override
  bool moveNext() {
    if (statement.finalizable._closed || statement._currentCursor != this) {
      return false;
    }

    final result = statement._step();

    if (result == SqlError.SQLITE_ROW) {
      final rowData = <Object?>[
        for (var i = 0; i < columnCount; i++) statement._readValue(i)
      ];

      current = Row(this, rowData);
      return true;
    }

    // We're at the end of the result set or encountered an exception here.
    statement._currentCursor = null;

    if (result != SqlError.SQLITE_OK && result != SqlError.SQLITE_DONE) {
      throwException(
        statement.database,
        result,
        operation: 'iterating through statement',
        previousStatement: statement.sql,
        statementArgs: statement._latestArguments,
      );
    }

    return false;
  }
}
