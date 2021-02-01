part of 'implementation.dart';

class PreparedStatementImpl implements PreparedStatement {
  final Pointer<sqlite3_stmt> _stmt;
  final DatabaseImpl _db;

  bool _closed = false;

  bool _variablesBound = false;
  final List<Pointer> _allocatedWhileBinding = [];

  Bindings get _bindings => _db._bindings;

  PreparedStatementImpl(this._stmt, this._db);

  @override
  int get parameterCount {
    return _bindings.sqlite3_bind_parameter_count(_stmt);
  }

  @override
  Pointer<void> get handle => _stmt;

  @override
  void execute([List<Object?> parameters = const <Object>[]]) {
    _ensureNotFinalized();
    _ensureMatchingParameters(parameters);

    _reset();
    _bindParams(parameters);

    final result = _step();
    if (result != SQLITE_OK && result != SQLITE_DONE) {
      throwException(_db, result);
    }
  }

  @override
  ResultSet select([List<Object?> parameters = const <Object>[]]) {
    _ensureNotFinalized();
    _ensureMatchingParameters(parameters);

    _reset();
    _bindParams(parameters);

    final columnCount = _bindings.sqlite3_column_count(_stmt);

    final names = [
      for (var i = 0; i < columnCount; i++)
        // name pointer doesn't need to be disposed, that happens when we
        // finalize
        _bindings.sqlite3_column_name(_stmt, i).readString()
    ];
    final rows = <List<Object?>>[];

    int resultCode;
    while ((resultCode = _step()) == SQLITE_ROW) {
      rows.add(<Object?>[for (var i = 0; i < columnCount; i++) _readValue(i)]);
    }

    if (resultCode != SQLITE_OK && resultCode != SQLITE_DONE) {
      throwException(_db, resultCode);
    }

    return ResultSet(names, rows);
  }

  @override
  void dispose() {
    if (!_closed) {
      _closed = true;

      _reset();
      _bindings.sqlite3_finalize(_stmt);
      _db._handleFinalized(this);
    }
  }

  void _reset() {
    if (_variablesBound) {
      _bindings.sqlite3_reset(_stmt);
      _variablesBound = false;
    }

    for (final pointer in _allocatedWhileBinding) {
      pointer.free();
    }
    _allocatedWhileBinding.clear();
  }

  void _bindParams(List<Object?>? params) {
    if (params == null || params.isEmpty) return;

    // variables in sqlite are 1-indexed
    for (var i = 1; i <= params.length; i++) {
      final Object? param = params[i - 1];

      if (param == null) {
        _bindings.sqlite3_bind_null(_stmt, i);
      } else if (param is int) {
        _bindings.sqlite3_bind_int64(_stmt, i, param);
      } else if (param is double) {
        _bindings.sqlite3_bind_double(_stmt, i, param.toDouble());
      } else if (param is String) {
        final bytes = utf8.encode(param);
        final ptr = allocateBytes(bytes);
        _allocatedWhileBinding.add(ptr);

        _bindings.sqlite3_bind_text(
            _stmt, i, ptr.cast(), bytes.length, nullPtr());
      } else if (param is List<int>) {
        if (param.isEmpty) {
          // malloc(0) is implementation-defined and might return a null
          // pointer, which is not what we want: Passing a null-pointer to
          // sqlite3_bind_blob will always bind NULL. So, we just pass 0x1 and
          // set a length of 0
          _bindings.sqlite3_bind_blob64(
              _stmt, i, Pointer.fromAddress(1), param.length, nullPtr());
        } else {
          final ptr = allocateBytes(param).cast<Void>();

          _bindings.sqlite3_bind_blob64(_stmt, i, ptr, param.length, nullPtr());
          _allocatedWhileBinding.add(ptr);
        }
      } else {
        throw ArgumentError.value(
          param,
          'params[$i]',
          'Allowed parameters must either be null or an int, num, String or '
              'List<int>.',
        );
      }
    }

    _variablesBound = true;
  }

  Object? _readValue(int index) {
    final type = _bindings.sqlite3_column_type(_stmt, index);
    switch (type) {
      case SQLITE_INTEGER:
        return _bindings.sqlite3_column_int64(_stmt, index);
      case SQLITE_FLOAT:
        return _bindings.sqlite3_column_double(_stmt, index);
      case SQLITE_TEXT:
        final length = _bindings.sqlite3_column_bytes(_stmt, index);
        return _bindings.sqlite3_column_text(_stmt, index).readString(length);
      case SQLITE_BLOB:
        final length = _bindings.sqlite3_column_bytes(_stmt, index);
        if (length == 0) {
          // sqlite3_column_blob returns a null pointer for non-null blobs with
          // a length of 0. Note that we can distinguish this from a proper null
          // by checking the type (which isn't SQLITE_NULL)
          return Uint8List(0);
        }
        return _bindings.sqlite3_column_blob(_stmt, index).copyRange(length);
      case SQLITE_NULL:
      default:
        return null;
    }
  }

  int _step() => _bindings.sqlite3_step(_stmt);

  void _ensureNotFinalized() {
    if (_closed) {
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
}
