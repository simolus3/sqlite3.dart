part of 'implementation.dart';

/// Contains the state of a database needed for finalization.
///
/// This is extracted into separate object so that it can be used as a
/// finalization token. It will get disposed when the main database is no longer
/// reachable without being closed.
class _FinalizableDatabase extends FinalizablePart {
  final Bindings _bindings;
  final Pointer<sqlite3> _handle;
  final List<_FinalizableStatement> _statements = [];
  final List<Pointer<Void>> _furtherAllocations = [];

  _FinalizableDatabase(this._bindings, this._handle);

  @override
  void dispose() {
    for (final stmt in _statements) {
      stmt.dispose();
    }

    final code = _bindings.sqlite3_close_v2(_handle);
    SqliteException? exception;
    if (code != SqlError.SQLITE_OK) {
      exception = createExceptionRaw(_bindings, _handle, code);
    }

    for (final additional in _furtherAllocations) {
      additional.free();
    }

    // we don't need to deallocate the _db pointer, sqlite takes care of that
    if (exception != null) {
      throw exception;
    }
  }
}

class DatabaseImpl extends Database {
  final BindingsWithLibrary _library;
  final Bindings _bindings;

  final _FinalizableDatabase _finalizable;
  final Finalizer<FinalizablePart> _finalizer = disposeFinalizer;

  late final _DatabaseUpdates _updates = _DatabaseUpdates(this);

  bool _isClosed = false;

  DatabaseImpl(this._library, Pointer<sqlite3> handle)
      : _finalizable = _FinalizableDatabase(_library.bindings, handle),
        this._bindings = _library.bindings {
    _finalizer.attach(this, _finalizable, detach: this);
  }

  factory DatabaseImpl.open(
    BindingsWithLibrary library,
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  }) {
    final bindings = library.bindings;
    bindingsForStore = bindings;

    final flags = flagsForOpen(mode: mode, uri: uri, mutex: mutex);

    final namePtr = allocateZeroTerminated(filename);
    final outDb = allocate<Pointer<sqlite3>>();
    final vfsPtr =
        vfs == null ? nullPtr<sqlite3_char>() : allocateZeroTerminated(vfs);

    final result = bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);

    final dbPtr = outDb.value;

    // Free pointers we allocated
    namePtr.free();
    outDb.free();
    if (vfs != null) vfsPtr.free();

    if (result != SqlError.SQLITE_OK) {
      bindings.sqlite3_close_v2(dbPtr);
      throw createExceptionRaw(bindings, dbPtr, result);
    }

    bindings.sqlite3_extended_result_codes(dbPtr, 1);
    return DatabaseImpl(library, dbPtr);
  }

  @override
  int get lastInsertRowId {
    return _bindings.sqlite3_last_insert_rowid(_handle);
  }

  @override
  Stream<SqliteUpdate> get updates => _updates.updates;

  Pointer<sqlite3> get _handle => _finalizable._handle;

  @override
  Pointer<void> get handle => _handle;

  @override
  int getUpdatedRows() {
    return _bindings.sqlite3_changes(_handle);
  }

  @override
  void execute(String sql, [List<Object?> parameters = const []]) {
    if (parameters.isEmpty) {
      // Use sqlite3_exec since that can run multiple statements at once.
      _ensureOpen();

      final sqlPtr = allocateZeroTerminated(sql);
      final errorOut = allocate<Pointer<sqlite3_char>>();

      final result = _bindings.sqlite3_exec(
          _handle, sqlPtr, nullPtr(), nullPtr(), errorOut);
      sqlPtr.free();

      final errorPtr = errorOut.value;
      errorOut.free();

      String? errorMsg;
      if (!errorPtr.isNullPointer) {
        errorMsg = errorPtr.readString();
        // The message was allocated from sqlite3, we need to free it
        _bindings.sqlite3_free(errorPtr.cast());
      }

      if (result != SqlError.SQLITE_OK) {
        throw SqliteException(result, errorMsg ?? 'unknown error', null, sql);
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
  PreparedStatement prepare(String sql,
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
  List<PreparedStatement> prepareMultiple(String sql,
      {bool persistent = false, bool vtab = true}) {
    return _prepareInternal(sql, persistent: persistent, vtab: vtab);
  }

  List<PreparedStatement> _prepareInternal(String sql,
      {bool persistent = false,
      bool vtab = true,
      int? maxStatements,
      bool checkNoTail = false}) {
    _ensureOpen();

    final stmtOut = allocate<Pointer<sqlite3_stmt>>();
    final pzTail = allocate<Pointer<sqlite3_char>>();

    final bytes = utf8.encode(sql);
    final sqlPtr = allocateBytes(bytes);

    var prepFlags = 0;
    if (persistent) {
      prepFlags |= SqlPrepareFlag.SQLITE_PREPARE_PERSISTENT;
    }
    if (!vtab) {
      prepFlags |= SqlPrepareFlag.SQLITE_PREPARE_NO_VTAB;
    }

    final createdStatements = <PreparedStatementImpl>[];
    var offset = 0;

    void freeIntermediateResults() {
      stmtOut.free();
      sqlPtr.free();
      pzTail.free();

      for (final stmt in createdStatements) {
        stmt.dispose();
      }
    }

    int prepare() {
      // Use prepare_v3 if supported, fall-back to prepare_v2 otherwise
      if (_library.supportsOpenV3) {
        final function = _library.appropriateOpenFunction
            .cast<NativeFunction<sqlite3_prepare_v3_native>>()
            .asFunction<sqlite3_prepare_v3_dart>();

        return function(
          _handle,
          sqlPtr.elementAt(offset).cast(),
          bytes.length - offset,
          prepFlags,
          stmtOut,
          pzTail,
        );
      } else {
        assert(
          prepFlags == 0,
          'Used custom preparation flags, but the loaded sqlite library does '
          'not support prepare_v3',
        );

        final function = _library.appropriateOpenFunction
            .cast<NativeFunction<sqlite3_prepare_v2_native>>()
            .asFunction<sqlite3_prepare_v2_dart>();

        return function(
          _handle,
          sqlPtr.elementAt(offset).cast(),
          bytes.length - offset,
          stmtOut,
          pzTail,
        );
      }
    }

    while (offset < bytes.length) {
      final resultCode = prepare();

      if (resultCode != SqlError.SQLITE_OK) {
        freeIntermediateResults();
        throwException(this, resultCode, sql);
      }

      final stmtPtr = stmtOut.value;
      final endOffset = pzTail.value.address - sqlPtr.address;

      // prepare can return a null pointer with SQLITE_OK if only whitespace
      // or comments were parsed. That's fine, just skip over it then.
      if (!stmtPtr.isNullPointer) {
        final sqlForStatement = utf8.decoder.convert(bytes, offset, endOffset);
        final stmt = PreparedStatementImpl(sqlForStatement, stmtPtr, this);

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
        offset = pzTail.value.address - sqlPtr.address;

        final stmtPtr = stmtOut.value;

        if (!stmtPtr.isNullPointer) {
          // Had an unexpected trailing statement -> throw!
          createdStatements.add(PreparedStatementImpl('', stmtPtr, this));
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

    stmtOut.free();
    sqlPtr.free();
    pzTail.free();

    for (final created in createdStatements) {
      _finalizable._statements.add(created._finalizable);
    }

    return createdStatements;
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
  void createCollation({
    required String name,
    required CollatingFunction function,
  }) {
    final storedFunction = functionStore.registerCollating(function);
    final namePtr = _functionName(name);

    final result = _bindings.sqlite3_create_collation_v2(
      _handle,
      namePtr.cast(), // zFunctionName
      SqlTextEncoding.SQLITE_UTF8,
      storedFunction.applicationData.cast(),
      storedFunction.xCompare!.cast(),
      storedFunction.xDestroy.cast(),
    );
    namePtr.free();

    if (result != SqlError.SQLITE_OK) {
      throwException(this, result);
    }
  }

  @override
  void createFunction({
    required String functionName,
    required ScalarFunction function,
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
      eTextRep(deterministic, directOnly),
      storedFunction.applicationData.cast(),
      storedFunction.xFunc!.cast(),
      nullPtr(),
      nullPtr(),
      storedFunction.xDestroy.cast(),
    );
    namePtr.free();

    if (result != SqlError.SQLITE_OK) {
      throwException(this, result);
    }
  }

  @override
  void createAggregateFunction<V>({
    required String functionName,
    required AggregateFunction<V> function,
    AllowedArgumentCount argumentCount = const AllowedArgumentCount.any(),
    bool deterministic = false,
    bool directOnly = true,
  }) {
    final namePtr = _functionName(functionName);
    int result;

    if (function is WindowFunction<V>) {
      final storedFunction = functionStore.registerWindow(function);

      result = _bindings.sqlite3_create_window_function(
        _handle,
        namePtr.cast(),
        argumentCount.allowedArgs,
        eTextRep(deterministic, directOnly),
        storedFunction.applicationData.cast(),
        storedFunction.xStep!.cast(),
        storedFunction.xFinal!.cast(),
        storedFunction.xValue!.cast(),
        storedFunction.xInverse!.cast(),
        storedFunction.xDestroy.cast(),
      );
    } else {
      final storedFunction = functionStore.registerAggregate(function);
      result = _bindings.sqlite3_create_function_v2(
        _handle,
        namePtr.cast(),
        argumentCount.allowedArgs,
        eTextRep(deterministic, directOnly),
        storedFunction.applicationData.cast(),
        nullPtr(),
        storedFunction.xStep!.cast(),
        storedFunction.xFinal!.cast(),
        storedFunction.xDestroy.cast(),
      );
    }

    namePtr.free();

    if (result != SqlError.SQLITE_OK) {
      throwException(this, result);
    }
  }

  @override
  void dispose() {
    if (_isClosed) return;

    _finalizer.detach(this);
    _isClosed = true;
    _updates.close();

    _finalizable.dispose();
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw StateError('This database has already been closed');
    }
  }

  void _handleFinalized(PreparedStatementImpl stmt) {
    if (!_isClosed) {
      _finalizable._statements.remove(stmt._finalizable);
    }
  }

  /// check if this is a in-memory database
  @visibleForTesting
  bool isInMemory() {
    final zDbName = allocateZeroTerminated('main');
    final pFileName = _bindings.sqlite3_db_filename(_handle, zDbName);

    zDbName.free();

    return pFileName.isNullPointer || pFileName.readString().isEmpty;
  }

  /// Ported from https://www.sqlite.org/backup.html Example 1
  void _loadOrSaveInMemoryDatabase(Database other, bool isSave) {
    final fromDatabase = isSave ? this : other;
    final toDatabase = isSave ? other : this;

    final zDestDb = allocateZeroTerminated('main');
    final zSrcDb = allocateZeroTerminated('main');

    final pBackup = _bindings.sqlite3_backup_init(
        toDatabase.handle.cast(), zDestDb, fromDatabase.handle.cast(), zSrcDb);

    if (!pBackup.isNullPointer) {
      _bindings.sqlite3_backup_step(pBackup, -1);
      _bindings.sqlite3_backup_finish(pBackup);
    }

    final extendedErrorCode =
        _bindings.sqlite3_extended_errcode(toDatabase.handle.cast());
    final errorCode = extendedErrorCode & 0xFF;

    zDestDb.free();
    zSrcDb.free();

    if (errorCode != SqlError.SQLITE_OK) {
      if (errorCode != SqlError.SQLITE_OK) {
        throw createExceptionFromExtendedCode(
            _bindings, _handle, errorCode, extendedErrorCode);
      }
    }
  }

  /// Ported from https://www.sqlite.org/backup.html Example 2
  Stream<double> _backupDatabase(Database toDatabase) async* {
    final zDestDb = allocateZeroTerminated('main');
    final zSrcDb = allocateZeroTerminated('main');

    final pBackup = _bindings.sqlite3_backup_init(
        toDatabase.handle.cast(), zDestDb, _handle, zSrcDb);

    int returnCode;
    if (!pBackup.isNullPointer) {
      do {
        returnCode = _bindings.sqlite3_backup_step(pBackup, 5);

        final remaining = _bindings.sqlite3_backup_remaining(pBackup);
        final count = _bindings.sqlite3_backup_pagecount(pBackup);

        yield (count - remaining) / count;

        if (returnCode == SqlError.SQLITE_OK ||
            returnCode == SqlError.SQLITE_BUSY ||
            returnCode == SqlError.SQLITE_LOCKED) {
          //Give other threads the chance to work with the database
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      } while (returnCode == SqlError.SQLITE_OK ||
          returnCode == SqlError.SQLITE_BUSY ||
          returnCode == SqlError.SQLITE_LOCKED);

      _bindings.sqlite3_backup_finish(pBackup);
    }

    final extendedErrorCode =
        _bindings.sqlite3_extended_errcode(toDatabase.handle.cast());
    final errorCode = extendedErrorCode & 0xFF;

    zDestDb.free();
    zSrcDb.free();

    if (errorCode != SqlError.SQLITE_OK) {
      throw createExceptionFromExtendedCode(
          _bindings, _handle, errorCode, extendedErrorCode);
    }
  }

  /// Impl only, this should be only called right after opening a new in-memory
  /// database
  @internal
  void restore(Database fromDatabase) {
    if (!isInMemory()) {
      throw ArgumentError(
          'Restoring is only available for in-momory databases');
    }

    _loadOrSaveInMemoryDatabase(fromDatabase, false);
  }

  @override
  Stream<double> backup(Database toDatabase) {
    if (isInMemory()) {
      _loadOrSaveInMemoryDatabase(toDatabase, true);
      return const Stream.empty();
    } else {
      return _backupDatabase(toDatabase);
    }
  }
}
