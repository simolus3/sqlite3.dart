import 'dart:convert';
import 'dart:typed_data';

import '../common/constants.dart';
import '../common/impl/finalizer.dart';
import '../common/result_set.dart';
import '../common/statement.dart';
import 'bindings.dart';
import 'database.dart';

class WasmFinalizableStatement extends FinalizablePart {
  final Pointer statement;
  final WasmBindings bindings;

  final List<Pointer> _allocatedWhileBinding = [];
  var _variablesBound = false;
  var _closed = false;

  WasmFinalizableStatement(this.statement, this.bindings);

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;
      _reset();
      bindings.sqlite3_finalize(statement);
    }
  }

  void _reset() {
    if (_variablesBound) {
      bindings.sqlite3_reset(statement);
      _variablesBound = false;
    }

    for (final pointer in _allocatedWhileBinding) {
      bindings.free(pointer);
    }
    _allocatedWhileBinding.clear();
  }
}

class WasmStatement extends CommonPreparedStatement {
  final WasmDatabase database;
  final Pointer statement;
  final String sqlForStatement;

  final WasmFinalizableStatement finalizable;
  final Finalizer<FinalizablePart> _finalizer = disposeFinalizer;

  WasmBindings get bindings => database.bindings;

  _ActiveCursorIterator? _currentCursor;

  WasmStatement(this.database, this.statement, this.sqlForStatement)
      : finalizable = WasmFinalizableStatement(statement, database.bindings) {
    _finalizer.attach(this, finalizable, detach: this);
  }

  void _reset() {
    finalizable._reset();
    _currentCursor = null;
  }

  int _step() => bindings.sqlite3_step(statement);

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

  void _execute() {
    int result;

    // Users should be able to execute statements returning rows, so we should
    // call _step() to skip past rows.
    do {
      result = _step();
    } while (result == SqlError.SQLITE_ROW);

    if (result != SqlError.SQLITE_OK && result != SqlError.SQLITE_DONE) {
      database.throwException(result, sql);
    }
  }

  List<String> get _columnNames {
    final columnCount = bindings.sqlite3_column_count(statement);

    return [
      for (var i = 0; i < columnCount; i++)
        // name pointer doesn't need to be disposed, that happens when we
        // finalize
        bindings.memory.readString(bindings.sqlite3_column_name(statement, i)),
    ];
  }

  Object? _readValue(int index) {
    final type = bindings.sqlite3_column_type(statement, index);
    switch (type) {
      case SqlType.SQLITE_INTEGER:
        return bindings.sqlite3_column_int64(statement, index);
      case SqlType.SQLITE_FLOAT:
        return bindings.sqlite3_column_double(statement, index);
      case SqlType.SQLITE_TEXT:
        final length = bindings.sqlite3_column_bytes(statement, index);
        return bindings.memory
            .readString(bindings.sqlite3_column_text(statement, index), length);
      case SqlType.SQLITE_BLOB:
        final length = bindings.sqlite3_column_bytes(statement, index);
        if (length == 0) {
          // sqlite3_column_blob returns a null pointer for non-null blobs with
          // a length of 0. Note that we can distinguish this from a proper null
          // by checking the type (which isn't SQLITE_NULL)
          return Uint8List(0);
        }

        return bindings.memory
            .copyRange(bindings.sqlite3_column_blob(statement, index), length);
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

    finalizable._variablesBound = true;
  }

  void _bindMapParams(Map<String, Object?> params) {
    final expectedLength = parameterCount;

    if (params.isEmpty) {
      if (expectedLength != 0) {
        throw ArgumentError.value(params, 'params',
            'Expected $expectedLength parameters, but none were set.');
      }
      return;
    }

    for (final key in params.keys) {
      final Object? param = params[key];

      final keyBytes = utf8.encode(key);
      final keyPtr = bindings.allocateBytes(keyBytes, additionalLength: 1);
      finalizable._allocatedWhileBinding.add(keyPtr);
      final i = bindings.sqlite3_bind_parameter_index(statement, keyPtr);

      // SQL parameters are 1-indexed, so 0 indicates that no parameter with
      // that name was found.
      if (i == 0) {
        throw ArgumentError.value(params, 'params',
            'This statement contains no parameter named `$key`');
      }
      _bindParam(param, i);
    }

    // If we reached this point. All parameters from [params] were bound. Check
    // if the statement contains no additional parameters.
    if (expectedLength != params.length) {
      throw ArgumentError.value(
          params, 'params', 'Expected $expectedLength parameters');
    }

    finalizable._variablesBound = true;
  }

  void _bindParam(Object? param, int i) {
    if (param == null) {
      bindings.sqlite3_bind_null(statement, i);
    } else if (param is int) {
      bindings.sqlite3_bind_int64(statement, i, BigInt.from(param));
    } else if (param is BigInt) {
      bindings.sqlite3_bind_int64(statement, i, param);
    } else if (param is bool) {
      bindings.sqlite3_bind_int64(
          statement, i, param ? BigInt.one : BigInt.zero);
    } else if (param is num) {
      bindings.sqlite3_bind_double(statement, i, param.toDouble());
    } else if (param is String) {
      final bytes = utf8.encode(param);
      final ptr = bindings.allocateBytes(bytes);
      finalizable._allocatedWhileBinding.add(ptr);

      bindings.sqlite3_bind_text(statement, i, ptr, bytes.length, 0);
    } else if (param is List<int>) {
      if (param.isEmpty) {
        // malloc(0) is implementation-defined and might return a null
        // pointer, which is not what we want: Passing a null-pointer to
        // sqlite3_bind_blob will always bind NULL. So, we just pass 0x1 and
        // set a length of 0
        bindings.sqlite3_bind_blob64(statement, i, 1, param.length, 0);
      } else {
        final ptr = bindings.allocateBytes(param);

        bindings.sqlite3_bind_blob64(statement, i, ptr, param.length, 0);
        finalizable._allocatedWhileBinding.add(ptr);
      }
    } else {
      throw ArgumentError.value(
        param,
        'params[$i]',
        'Allowed parameters must either be null or bool, BigInt, num, String '
            'or List<int>.',
      );
    }
  }

  @override
  void dispose() {
    if (!finalizable._closed) {
      _finalizer.detach(this);
      finalizable.dispose();

      _currentCursor = null;
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
  int get parameterCount => bindings.sqlite3_bind_parameter_count(statement);

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
    return _currentCursor = _ActiveCursorIterator(this, names, null);
  }

  @override
  ResultSet selectMap(Map<String, Object?> parameters) {
    _ensureNotFinalized();

    _reset();
    _bindMapParams(parameters);

    return _selectResults();
  }

  ResultSet _selectResults() {
    final names = _columnNames;
    final columnCount = names.length;
    final rows = <List<Object?>>[];

    int resultCode;
    while ((resultCode = _step()) == SqlError.SQLITE_ROW) {
      rows.add(<Object?>[for (var i = 0; i < columnCount; i++) _readValue(i)]);
    }

    if (resultCode != SqlError.SQLITE_OK &&
        resultCode != SqlError.SQLITE_DONE) {
      database.throwException(resultCode, sql);
    }

    return ResultSet(names, null, rows);
  }

  @override
  String get sql => sqlForStatement;
}

class _ActiveCursorIterator extends IteratingCursor {
  final WasmStatement statement;
  final int columnCount;

  @override
  late Row current;

  _ActiveCursorIterator(
    this.statement,
    List<String> columnNames,
    List<String?>? tableNames,
  )   : columnCount = columnNames.length,
        super(columnNames, tableNames);

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
      statement.database.throwException(result, statement.sql);
    }

    return false;
  }
}
