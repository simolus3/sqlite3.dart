part of 'implementation.dart';

class DatabaseImpl implements Database {
  final Bindings _bindings;

  final Pointer<sqlite3> _handle;
  final List<PreparedStatementImpl> _statements = [];
  final List<Pointer<Void>> _furtherAllocations = [];

  bool _isClosed = false;

  DatabaseImpl(this._bindings, this._handle);

  factory DatabaseImpl.open(Bindings bindings, String filename,
      {String vfs, OpenMode mode = OpenMode.readWriteCreate}) {
    bindingsForStore = bindings;

    final flags = const {
      OpenMode.readOnly: SQLITE_OPEN_READONLY,
      OpenMode.readWrite: SQLITE_OPEN_READWRITE,
      OpenMode.readWriteCreate: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE,
    }[mode];

    final namePtr = allocateZeroTerminated(filename);
    final outDb = allocate<Pointer<sqlite3>>();
    final vfsPtr = vfs == null ? nullPtr<char>() : allocateZeroTerminated(vfs);

    final result = bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);

    final dbPtr = outDb.value;

    // Free pointers we allocated
    namePtr.free();
    outDb.free();
    vfsPtr.free();

    if (result != SQLITE_OK) {
      bindings.sqlite3_close_v2(dbPtr);
      throw createExceptionRaw(bindings, dbPtr, result);
    }

    bindings.sqlite3_extended_result_codes(dbPtr, 1);
    return DatabaseImpl(bindings, dbPtr);
  }

  @override
  int get lastInsertRowId {
    return _bindings.sqlite3_last_insert_rowid(_handle);
  }

  @override
  int get userVersion {
    final stmt = prepare('PRAGMA user_version;');
    final result = stmt.select();

    final version = result.first.columnAt(0) as int;
    stmt.dispose();
    return version;
  }

  @override
  set userVersion(int value) {
    execute('PRAGMA user_version = $value;');
  }

  @override
  int getUpdatedRows() {
    return _bindings.sqlite3_changes(_handle);
  }

  @override
  void execute(String sql) {
    _ensureOpen();

    final sqlPtr = allocateZeroTerminated(sql);
    final errorOut = allocate<Pointer<char>>();

    final result =
        _bindings.sqlite3_exec(_handle, sqlPtr, nullPtr(), nullPtr(), errorOut);
    sqlPtr.free();

    final errorPtr = errorOut.value;
    errorOut.free();

    String errorMsg;
    if (!errorPtr.isNullPointer) {
      errorMsg = errorPtr.readString();
      // The message was allocated from sqlite3, we need to free it
      _bindings.sqlite3_free(errorPtr.cast());
    }

    if (result != SQLITE_OK) {
      throw SqliteException(result, errorMsg);
    }
  }

  @override
  ResultSet select(String sql, [List<Object> parameters = const []]) {
    final stmt = prepare(sql);
    final result = stmt.select(parameters);
    stmt.dispose();
    return result;
  }

  @override
  PreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true}) {
    _ensureOpen();

    final stmtOut = allocate<Pointer<sqlite3_stmt>>();

    final bytes = utf8.encode(sql);
    final sqlPtr = allocateBytes(bytes);

    var prepFlags = 0;
    if (persistent) {
      prepFlags |= SQLITE_PREPARE_PERSISTENT;
    }
    if (!vtab) {
      prepFlags |= SQLITE_PREPARE_NO_VTAB;
    }

    int resultCode;
    if (_bindings.sqlite3_prepare_v3 != null) {
      resultCode = _bindings.sqlite3_prepare_v3(
        _handle,
        sqlPtr.cast(),
        bytes.length,
        prepFlags,
        stmtOut,
        nullPtr(),
      );
    } else {
      // Handle old version of sqlite (needed on Ubuntu 16.04)
      resultCode = _bindings.sqlite3_prepare_v2(
        _handle,
        sqlPtr.cast(),
        bytes.length,
        stmtOut,
        nullPtr(),
      );
    }

    final stmtPtr = stmtOut.value;
    stmtOut.free();
    if (resultCode != SQLITE_OK) {
      throwException(this, resultCode);
    }

    final stmt = PreparedStatementImpl(stmtPtr, this);

    _statements.add(stmt);
    return stmt;
  }

  int _eTextRep(bool deterministic, bool directOnly) {
    var flags = SQLITE_UTF8;
    if (deterministic) {
      flags |= SQLITE_DETERMINISTIC;
    }
    if (directOnly) {
      flags |= SQLITE_DIRECTONLY;
    }

    return flags;
  }

  Pointer<Uint8> _functionName(String functionName) {
    final functionNameBytes = utf8.encode(functionName);

    if (functionNameBytes.length > 255) {
      throw ArgumentError.value(functionName, 'functionName',
          'Must not exceed 255 bytes when utf-8 encoded');
    }

    return allocateBytes(functionNameBytes, additionalLength: 1);
  }

  @override
  void createFunction({
    @required String functionName,
    @required ScalarFunction function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
  }) {
    final storedFunction = functionStore.registerScalar(function);
    final namePtr = _functionName(functionName);

    final result = _bindings.sqlite3_create_function_v2(
      _handle,
      namePtr.cast(), // zFunctionName
      argumentCount.allowedArgs,
      _eTextRep(deterministic, directOnly),
      storedFunction.applicationData.cast(),
      storedFunction.xFunc.cast(),
      nullPtr(),
      nullPtr(),
      storedFunction.xDestroy.cast(),
    );
    namePtr.free();

    if (result != SQLITE_OK) {
      throwException(this, result);
    }
  }

  @override
  void createAggregateFunction<V>({
    String functionName,
    AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
  }) {
    final storedFunction = functionStore.registerAggregate(function);
    final namePtr = _functionName(functionName);

    final result = _bindings.sqlite3_create_function_v2(
      _handle,
      namePtr.cast(),
      argumentCount.allowedArgs,
      _eTextRep(deterministic, directOnly),
      storedFunction.applicationData.cast(),
      nullPtr(),
      storedFunction.xStep.cast(),
      storedFunction.xFinal.cast(),
      storedFunction.xDestroy.cast(),
    );
    namePtr.free();

    if (result != SQLITE_OK) {
      throwException(this, result);
    }
  }

  @override
  void dispose() {
    if (_isClosed) return;

    _isClosed = true;
    for (final stmt in _statements) {
      stmt.dispose();
    }

    final code = _bindings.sqlite3_close_v2(_handle);
    SqliteException exception;
    if (code != SQLITE_OK) {
      exception = createException(this, code);
    }

    for (final additional in _furtherAllocations) {
      additional.free();
    }

    // we don't need to deallocate the _db pointer, sqlite takes care of that
    if (exception != null) {
      throw exception;
    }
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('This database has already been closed');
    }
  }

  void _handleFinalized(PreparedStatementImpl stmt) {
    if (!_isClosed) {
      _statements.remove(stmt);
    }
  }
}
