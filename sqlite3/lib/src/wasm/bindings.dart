import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:sqlite3/src/vfs.dart';

import '../constants.dart';
import '../functions.dart';
import '../implementation/bindings.dart';
import '../implementation/exception.dart';
import 'wasm_interop.dart' as wasm;
import 'sqlite3_wasm.g.dart';
import 'wasm_interop.dart';

// ignore_for_file: non_constant_identifier_names

final class WasmSqliteBindings extends RawSqliteBindings {
  final wasm.WasmBindings bindings;

  WasmSqliteBindings(this.bindings);

  @override
  String? get sqlite3_temp_directory {
    final charPtr = bindings.sqlite3_temp_directory;
    if (charPtr == 0) {
      return null;
    } else {
      return bindings.memory.readString(charPtr);
    }
  }

  @override
  set sqlite3_temp_directory(String? value) {
    if (value == null) {
      bindings.sqlite3_temp_directory = 0;
    } else {
      bindings.sqlite3_temp_directory = bindings.allocateZeroTerminated(value);
    }
  }

  @override
  String sqlite3_errstr(int extendedErrorCode) {
    return bindings.memory
        .readString(bindings.sqlite3_errstr(extendedErrorCode));
  }

  @override
  String sqlite3_libversion() {
    return bindings.memory.readString(bindings.sqlite3_libversion());
  }

  @override
  int sqlite3_libversion_number() {
    return bindings.sqlite3_libversion_number();
  }

  @override
  SqliteResult<RawSqliteDatabase> sqlite3_open_v2(
      String name, int flags, String? zVfs) {
    final namePtr = bindings.allocateZeroTerminated(name);
    final outDb = bindings.malloc(wasm.WasmBindings.pointerSize);
    final vfsPtr = zVfs == null ? 0 : bindings.allocateZeroTerminated(zVfs);

    final result = bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);
    final dbPtr = bindings.memory.int32ValueOfPointer(outDb);

    // Free pointers we allocateed
    bindings
      ..free(namePtr)
      ..free(vfsPtr);
    if (zVfs != null) bindings.free(vfsPtr);

    return SqliteResult(result, WasmDatabase(bindings, dbPtr));
  }

  @override
  String sqlite3_sourceid() {
    return bindings.memory.readString(bindings.sqlite3_sourceid());
  }

  @override
  int sqlite3_initialize() {
    return bindings.sqlite3_initialize();
  }

  @override
  void registerVirtualFileSystem(VirtualFileSystem vfs, int makeDefault) {
    final name = bindings.allocateZeroTerminated(vfs.name);
    final id = bindings.callbacks.registerVfs(vfs);

    final ptr = bindings.dart_sqlite3_register_vfs(name, id, makeDefault);
    if (ptr == 0) {
      throw StateError('could not register vfs');
    }
    DartCallbacks.sqliteVfsPointer[vfs] = ptr;
  }

  @override
  void unregisterVirtualFileSystem(VirtualFileSystem vfs) {
    final ptr = DartCallbacks.sqliteVfsPointer[vfs];
    if (ptr == null) {
      throw StateError('vfs has not been registered');
    }

    // zName field is the fifth field, after the (word-sized) iVersion, szOsFile,
    // maxPathname and pNext pointers.
    final zNamePtr = ptr + 4 * 4;
    final pAppDataPtr = zNamePtr + 4;

    bindings.sqlite3_vfs_unregister(ptr);
    bindings.free(zNamePtr);

    final dartId = bindings.memory.int32ValueOfPointer(pAppDataPtr);
    bindings.callbacks.registeredVfs.remove(dartId);
  }

  @override
  RawSqliteSession sqlite3session_create(RawSqliteDatabase db, String name) {
    final zDb = bindings.allocateZeroTerminated(name);
    final sessionPtr = bindings.malloc(WasmBindings.pointerSize);

    final result = bindings.sqlite3session_create(
      (db as WasmDatabase).db,
      zDb,
      sessionPtr,
    );

    final session = bindings.memory.int32ValueOfPointer(sessionPtr);
    bindings
      ..free(zDb)
      ..free(sessionPtr);

    if (result != 0) {
      throw createExceptionOutsideOfDatabase(this, result);
    }

    return WasmSession(this, session);
  }

  @override
  int sqlite3changeset_apply(
    RawSqliteDatabase database,
    Uint8List changeset,
    int Function(String tableName)? filter,
    int Function(int eConflict, RawChangesetIterator iter) conflict,
  ) {
    final callbacks = SessionApplyCallbacks(
      switch (filter) {
        null => null,
        final filter => (Pointer tableName) {
            final table = bindings.memory.readString(tableName);
            return filter(table);
          },
      },
      (int eConflict, Pointer iterator) {
        final impl = WasmChangesetIterator(this, iterator, owned: false);
        return conflict(eConflict, impl);
      },
    );
    final callbackId = bindings.callbacks.registerChangesetApply(callbacks);
    final changesetPtr = bindings.allocateBytes(changeset);

    final result = bindings.dart_sqlite3changeset_apply(
      (database as WasmDatabase).db,
      changeset.length,
      changesetPtr,
      callbackId,
      filter != null ? 1 : 0,
    );

    bindings.callbacks.sessionApply.remove(callbackId);
    bindings.free(changesetPtr);
    return result;
  }

  @override
  Uint8List sqlite3changeset_invert(Uint8List changeset) {
    final originalPtr = bindings.allocateBytes(changeset);
    final lengthPtr = bindings.malloc(WasmBindings.pointerSize);
    final outPtr = bindings.malloc(WasmBindings.pointerSize);
    final result = bindings.sqlite3changeset_invert(
        changeset.length, originalPtr, lengthPtr, outPtr);

    final length = bindings.memory.int32ValueOfPointer(lengthPtr);
    final inverted = bindings.memory.int32ValueOfPointer(outPtr);

    bindings
      ..free(originalPtr)
      ..free(lengthPtr)
      ..free(outPtr);

    if (result != 0) {
      throw createExceptionOutsideOfDatabase(this, result);
    }

    final out = bindings.memory.copyRange(inverted, length);
    bindings.sqlite3_free(inverted);
    return out;
  }

  @override
  RawChangesetIterator sqlite3changeset_start(Uint8List changeset) {
    final changesetPtr = bindings.allocateBytes(changeset);
    final outPtr = bindings.malloc(WasmBindings.pointerSize);
    final result =
        bindings.sqlite3changeset_start(outPtr, changeset.length, changesetPtr);

    final iterator = bindings.memory.int32ValueOfPointer(outPtr);
    bindings.free(outPtr);

    if (result != 0) {
      throw createExceptionOutsideOfDatabase(this, result);
    }
    return WasmChangesetIterator(this, iterator, dataPointer: changesetPtr);
  }
}

final class WasmDatabase extends RawSqliteDatabase {
  final wasm.WasmBindings bindings;
  final Pointer db;

  WasmDatabase(this.bindings, this.db);

  @override
  int sqlite3_close_v2() {
    return bindings.sqlite3_close_v2(db);
  }

  @override
  String sqlite3_errmsg() {
    return bindings.memory.readString(bindings.sqlite3_errmsg(db));
  }

  @override
  int sqlite3_extended_errcode() {
    return bindings.sqlite3_extended_errcode(db);
  }

  @override
  int sqlite3_error_offset() {
    return bindings.sqlite3_error_offset(db);
  }

  @override
  void sqlite3_extended_result_codes(int onoff) {
    bindings.sqlite3_extended_result_codes(db, onoff);
  }

  @override
  void deallocateAdditionalMemory() {}

  @override
  RawStatementCompiler newCompiler(List<int> utf8EncodedSql) {
    final ptr = bindings.allocateBytes(utf8EncodedSql);

    return WasmStatementCompiler(this, ptr);
  }

  @override
  int sqlite3_changes() => bindings.sqlite3_changes(db);

  @override
  int sqlite3_create_collation_v2({
    required Uint8List collationName,
    required int eTextRep,
    required RawCollation collation,
  }) {
    final ptr = bindings.allocateBytes(collationName, additionalLength: 1);
    final result = bindings.create_collation(
        db,
        ptr,
        eTextRep,
        bindings.callbacks.register(RegisteredFunctionSet(
          collation: collation,
        )));

    bindings.free(ptr);
    return result;
  }

  @override
  int sqlite3_create_function_v2({
    required Uint8List functionName,
    required int nArg,
    required int eTextRep,
    RawXFunc? xFunc,
    RawXStep? xStep,
    RawXFinal? xFinal,
  }) {
    final ptr = bindings.allocateBytes(functionName, additionalLength: 1);

    final int result;
    if (xFunc != null) {
      // Scalar function
      result = bindings.create_scalar_function(
        db,
        ptr,
        nArg,
        eTextRep,
        bindings.callbacks.register(RegisteredFunctionSet(xFunc: xFunc)),
      );
    } else {
      // Aggregate function
      result = bindings.create_aggregate_function(
        db,
        ptr,
        nArg,
        eTextRep,
        bindings.callbacks.register(
          RegisteredFunctionSet(xStep: xStep, xFinal: xFinal),
        ),
      );
    }

    bindings.free(ptr);
    return result;
  }

  @override
  int sqlite3_create_window_function({
    required Uint8List functionName,
    required int nArg,
    required int eTextRep,
    required RawXStep xStep,
    required RawXFinal xFinal,
    required RawXFinal xValue,
    required RawXStep xInverse,
  }) {
    final ptr = bindings.allocateBytes(functionName, additionalLength: 1);
    final result = bindings.create_window_function(
        db,
        ptr,
        nArg,
        eTextRep,
        bindings.callbacks.register(RegisteredFunctionSet(
          xStep: xStep,
          xFinal: xFinal,
          xValue: xValue,
          xInverse: xInverse,
        )));

    bindings.free(ptr);
    return result;
  }

  @override
  int sqlite3_exec(String sql) {
    final stmt = bindings.allocateZeroTerminated(sql);
    final result = bindings.sqlite3_exec(db, stmt, 0, 0, 0);
    bindings.free(stmt);
    return result;
  }

  @override
  int sqlite3_last_insert_rowid() {
    return bindings.sqlite3_last_insert_rowid(db);
  }

  @override
  void sqlite3_update_hook(RawUpdateHook? hook) {
    bindings.callbacks.installedUpdateHook = hook;

    bindings.dart_sqlite3_updates(db, hook != null ? 1 : -1);
  }

  @override
  void sqlite3_commit_hook(RawCommitHook? hook) {
    bindings.callbacks.installedCommitHook = hook;

    bindings.dart_sqlite3_commits(db, hook != null ? 1 : -1);
  }

  @override
  void sqlite3_rollback_hook(RawRollbackHook? hook) {
    bindings.callbacks.installedRollbackHook = hook;

    bindings.dart_sqlite3_rollbacks(db, hook != null ? 1 : -1);
  }

  @override
  int sqlite3_get_autocommit() {
    return bindings.sqlite3_get_autocommit(db);
  }

  @override
  int sqlite3_db_config(int op, int value) {
    return bindings.sqlite3_db_config(db, op, value);
  }
}

final class WasmStatementCompiler extends RawStatementCompiler {
  final WasmDatabase database;
  final Pointer sql;
  final Pointer stmtOut;
  final Pointer pzTail;

  WasmStatementCompiler(this.database, this.sql)
      : stmtOut = database.bindings.malloc(WasmBindings.pointerSize),
        pzTail = database.bindings.malloc(WasmBindings.pointerSize);

  @override
  void close() {
    database.bindings
      ..free(sql)
      ..free(stmtOut)
      ..free(pzTail);
  }

  @override
  int get endOffset {
    final bindings = database.bindings;
    return bindings.memory.int32ValueOfPointer(pzTail) - sql;
  }

  @override
  SqliteResult<RawSqliteStatement?> sqlite3_prepare(
      int byteOffset, int length, int prepFlag) {
    final result = database.bindings.sqlite3_prepare_v3(
      database.db,
      sql + byteOffset,
      length,
      prepFlag,
      stmtOut,
      pzTail,
    );

    final stmt = database.bindings.memory.int32ValueOfPointer(stmtOut);
    final libraryStatement = stmt == 0 ? null : WasmStatement(database, stmt);

    return SqliteResult(result, libraryStatement);
  }
}

final class WasmStatement extends RawSqliteStatement {
  final WasmDatabase database;
  final Pointer stmt;
  final WasmBindings bindings;

  final List<Pointer> _allocatedArguments = [];

  WasmStatement(this.database, this.stmt) : bindings = database.bindings;

  @override
  void deallocateArguments() {
    for (final arg in _allocatedArguments) {
      bindings.free(arg);
    }
    _allocatedArguments.clear();
  }

  @override
  int sqlite3_bind_blob64(int index, List<int> value) {
    final ptr = bindings.allocateBytes(value);
    _allocatedArguments.add(ptr);

    return bindings.sqlite3_bind_blob64(stmt, index, ptr, value.length, 0);
  }

  @override
  int sqlite3_bind_double(int index, double value) {
    return bindings.sqlite3_bind_double(stmt, index, value);
  }

  @override
  int sqlite3_bind_int64(int index, int value) {
    return bindings.sqlite3_bind_int(stmt, index, value);
  }

  @override
  int sqlite3_bind_int64BigInt(int index, BigInt value) {
    return bindings.sqlite3_bind_int64(stmt, index, value);
  }

  @override
  int sqlite3_bind_null(int index) {
    return bindings.sqlite3_bind_null(stmt, index);
  }

  @override
  int sqlite3_bind_parameter_count() {
    return bindings.sqlite3_bind_parameter_count(stmt);
  }

  @override
  int sqlite3_stmt_isexplain() {
    return bindings.sqlite3_stmt_isexplain(stmt);
  }

  @override
  int sqlite3_stmt_readonly() {
    return bindings.sqlite3_stmt_readonly(stmt);
  }

  @override
  int sqlite3_bind_parameter_index(String name) {
    final namePtr = bindings.allocateZeroTerminated(name);

    final result = bindings.sqlite3_bind_parameter_index(stmt, namePtr);
    bindings.free(namePtr);

    return result;
  }

  @override
  int sqlite3_bind_text(int index, String value) {
    final encoded = utf8.encode(value);
    final ptr = bindings.allocateBytes(encoded);
    _allocatedArguments.add(ptr);

    return bindings.sqlite3_bind_text(stmt, index, ptr, encoded.length, 0);
  }

  @override
  Uint8List sqlite3_column_bytes(int index) {
    final length = bindings.sqlite3_column_bytes(stmt, index);
    final ptr = bindings.sqlite3_column_blob(stmt, index);

    return bindings.memory.copyRange(ptr, length);
  }

  @override
  int sqlite3_column_count() {
    return bindings.sqlite3_column_count(stmt);
  }

  @override
  double sqlite3_column_double(int index) {
    return bindings.sqlite3_column_double(stmt, index);
  }

  @override
  int sqlite3_column_int64(int index) {
    final jsBigInt = bindings.sqlite3_column_int64(stmt, index);
    return jsBigInt.asDartInt;
  }

  @override
  Object sqlite3_column_int64OrBigInt(int index) {
    final jsBigInt = bindings.sqlite3_column_int64(stmt, index);
    return jsBigInt.toDart();
  }

  @override
  String sqlite3_column_name(int index) {
    final namePtr = bindings.sqlite3_column_name(stmt, index);
    return bindings.memory.readString(namePtr);
  }

  @override
  String? sqlite3_column_table_name(int index) {
    return null;
  }

  @override
  String sqlite3_column_text(int index) {
    final ptr = bindings.sqlite3_column_text(stmt, index);
    return bindings.memory.readString(ptr);
  }

  @override
  int sqlite3_column_type(int index) {
    return bindings.sqlite3_column_type(stmt, index);
  }

  @override
  void sqlite3_finalize() {
    bindings.sqlite3_finalize(stmt);
  }

  @override
  void sqlite3_reset() {
    bindings.sqlite3_reset(stmt);
  }

  @override
  int sqlite3_step() {
    return bindings.sqlite3_step(stmt);
  }

  @override
  bool get supportsReadingTableNameForColumn => false;
}

final class WasmContext extends RawSqliteContext {
  final WasmBindings bindings;
  final Pointer context;
  final DartCallbacks callbacks;

  WasmContext(this.bindings, this.context, this.callbacks);

  Pointer get _rawAggregateContext {
    final agCtxPtr = bindings.sqlite3_aggregate_context(context, 4);

    if (agCtxPtr == 0) {
      // We can't run without our 4 bytes! This indicates an out-of-memory error
      throw StateError(
          'Internal error while allocating sqlite3 aggregate context (OOM?)');
    }

    return agCtxPtr;
  }

  @override
  AggregateContext<Object?>? get dartAggregateContext {
    final agCtxPtr = _rawAggregateContext;
    final value = bindings.memory.int32ValueOfPointer(agCtxPtr);

    // Ok, we have a pointer (that sqlite3 zeroes out for us). Our state counter
    // starts at one, so if it's still zero we don't have a Dart context yet.
    if (value == 0) {
      return null;
    } else {
      return callbacks.aggregateContexts[value];
    }
  }

  @override
  set dartAggregateContext(AggregateContext<Object?>? value) {
    final ptr = _rawAggregateContext;
    final id = callbacks.aggregateContextId++;
    callbacks.aggregateContexts[id] = ArgumentError.checkNotNull(value);

    bindings.memory.setInt32Value(ptr, id);
  }

  @override
  void sqlite3_result_blob64(List<int> blob) {
    final ptr = bindings.allocateBytes(blob);

    bindings.sqlite3_result_blob64(
        context, ptr, blob.length, SqlSpecialDestructor.SQLITE_TRANSIENT);
    bindings.free(ptr);
  }

  @override
  void sqlite3_result_double(double value) {
    return bindings.sqlite3_result_double(context, value);
  }

  @override
  void sqlite3_result_error(String message) {
    final encoded = utf8.encode(message);
    final ptr = bindings.allocateBytes(encoded);

    bindings.sqlite3_result_error(context, ptr, encoded.length);
    bindings.free(ptr);
  }

  @override
  void sqlite3_result_int64(int value) {
    bindings.sqlite3_result_int64(context, BigInt.from(value));
  }

  @override
  void sqlite3_result_int64BigInt(BigInt value) {
    bindings.sqlite3_result_int64(context, value);
  }

  @override
  void sqlite3_result_null() {
    return bindings.sqlite3_result_null(context);
  }

  @override
  void sqlite3_result_text(String text) {
    final encoded = utf8.encode(text);
    final ptr = bindings.allocateBytes(encoded);

    bindings.sqlite3_result_text(
        context, ptr, encoded.length, SqlSpecialDestructor.SQLITE_TRANSIENT);
    bindings.free(ptr);
  }

  @override
  void sqlite3_result_subtype(int value) {
    bindings.sqlite3_result_subtype(context, value);
  }
}

final class WasmValue extends RawSqliteValue {
  final WasmBindings bindings;
  final Pointer value;

  WasmValue(this.bindings, this.value);

  @override
  Uint8List sqlite3_value_blob() {
    final length = bindings.sqlite3_value_bytes(value);
    return bindings.memory
        .copyRange(bindings.sqlite3_value_blob(value), length);
  }

  @override
  double sqlite3_value_double() {
    return bindings.sqlite3_value_double(value);
  }

  @override
  int sqlite3_value_int64() {
    return bindings.sqlite3_value_int64(value).asDartInt;
  }

  @override
  String sqlite3_value_text() {
    final length = bindings.sqlite3_value_bytes(value);
    return bindings.memory
        .readString(bindings.sqlite3_value_text(value), length);
  }

  @override
  int sqlite3_value_type() {
    return bindings.sqlite3_value_type(value);
  }

  @override
  int sqlite3_value_subtype() {
    return bindings.sqlite3_value_subtype(value);
  }
}

class WasmValueList extends ListBase<WasmValue> {
  final WasmBindings bindings;
  @override
  final int length;
  final Pointer value;

  WasmValueList(this.bindings, this.length, this.value);

  @override
  set length(int value) {
    throw UnsupportedError('Setting length in WasmValueList');
  }

  @override
  WasmValue operator [](int index) {
    final valuePtr = bindings.memory
        .int32ValueOfPointer(value + index * WasmBindings.pointerSize);
    return WasmValue(bindings, valuePtr);
  }

  @override
  void operator []=(int index, WasmValue value) {
    throw UnsupportedError('Setting element in WasmValueList');
  }
}

final class WasmSession extends RawSqliteSession {
  static final Finalizer<(WasmBindings, int)> _finalizer = Finalizer((args) {
    args.$1.sqlite3session_delete(args.$2);
  });

  final WasmSqliteBindings bindings;
  final int pointer; // the sqlite3_session ptr
  final Object detach = Object();

  final WasmBindings _bindings;

  WasmSession(this.bindings, this.pointer) : _bindings = bindings.bindings {
    _finalizer.attach(this, (_bindings, pointer), detach: detach);
  }

  @override
  int sqlite3session_attach([String? name]) {
    final zTab = name == null ? 0 : _bindings.malloc(WasmBindings.pointerSize);
    final resultCode = _bindings.sqlite3session_attach(pointer, zTab);
    if (name != null) {
      _bindings.free(zTab);
    }

    return resultCode;
  }

  Uint8List _extractBytes(int Function(Pointer, Pointer, Pointer) raw) {
    final sizePtr = _bindings.malloc(WasmBindings.pointerSize);
    final patchsetPtr = _bindings.malloc(WasmBindings.pointerSize);

    final rc = raw(pointer, sizePtr, patchsetPtr);
    if (rc != 0) {
      throw createExceptionOutsideOfDatabase(bindings, rc);
    }

    final length = _bindings.memory.int32ValueOfPointer(sizePtr);
    final patchset = _bindings.memory.int32ValueOfPointer(patchsetPtr);
    _bindings
      ..free(sizePtr)
      ..free(patchsetPtr);

    final bytes = _bindings.memory.copyRange(patchset, length);
    _bindings.sqlite3_free(patchset);

    return bytes;
  }

  @override
  Uint8List sqlite3session_changeset() {
    return _extractBytes(_bindings.sqlite3session_changeset);
  }

  @override
  Uint8List sqlite3session_patchset() {
    return _extractBytes(_bindings.sqlite3session_patchset);
  }

  @override
  void sqlite3session_delete() {
    _finalizer.detach(this);
    _bindings.sqlite3session_delete(pointer);
  }

  @override
  int sqlite3session_diff(String fromDb, String table) {
    final dbPtr = _bindings.allocateZeroTerminated(fromDb);
    final tableptr = _bindings.allocateZeroTerminated(table);
    final code = _bindings.sqlite3session_diff(pointer, dbPtr, tableptr, 0);
    _bindings
      ..free(dbPtr)
      ..free(tableptr);

    return code;
  }

  @override
  int sqlite3session_enable(int enable) {
    return _bindings.sqlite3session_enable(pointer, enable);
  }

  @override
  int sqlite3session_indirect(int indirect) {
    return _bindings.sqlite3session_indirect(pointer, indirect);
  }

  @override
  int sqlite3session_isempty() => _bindings.sqlite3session_isempty(pointer);
}

final class WasmChangesetIterator extends RawChangesetIterator {
  static final Finalizer<(WasmBindings, int?, int)> _finalizer =
      Finalizer((args) {
    if (args.$2 case final underlyingBytes?) {
      args.$1.free(underlyingBytes);
    }

    args.$1.sqlite3changeset_finalize(args.$3);
  });

  final WasmSqliteBindings bindings;

  /// If this iterator was created from an uint8list allocated when creating it,
  /// the pointer towards that.
  final int? dataPointer;
  final int pointer; // the sqlite3_changeset_iter ptr
  final Object detach = Object();

  final WasmBindings _bindings;

  WasmChangesetIterator(this.bindings, this.pointer,
      {this.dataPointer, bool owned = true})
      : _bindings = bindings.bindings {
    if (owned) {
      _finalizer.attach(this, (_bindings, dataPointer, pointer),
          detach: detach);
    }
  }

  @override
  int sqlite3changeset_finalize() {
    _finalizer.detach(detach);
    if (dataPointer case final data?) {
      _bindings.free(data);
    }

    return _bindings.sqlite3changeset_finalize(pointer);
  }

  @override
  int sqlite3changeset_next() => _bindings.sqlite3changeset_next(pointer);

  SqliteResult<RawSqliteValue?> _extractValue(
      int Function(Pointer, int, Pointer) extract, int index) {
    final outValue = _bindings.malloc(WasmBindings.pointerSize);
    final resultCode = extract(pointer, index, outValue);
    final value = _bindings.memory.int32ValueOfPointer(outValue);
    _bindings.free(outValue);

    return SqliteResult(
        resultCode, value != 0 ? WasmValue(_bindings, value) : null);
  }

  @override
  SqliteResult<RawSqliteValue?> sqlite3changeset_old(int columnNumber) {
    return _extractValue(_bindings.sqlite3changeset_old, columnNumber);
  }

  @override
  SqliteResult<RawSqliteValue?> sqlite3changeset_new(int columnNumber) {
    return _extractValue(_bindings.sqlite3changeset_new, columnNumber);
  }

  @override
  RawChangeSetOp sqlite3changeset_op() {
    final outTable = _bindings.malloc(WasmBindings.pointerSize);
    final outColCount = _bindings.malloc(WasmBindings.pointerSize);
    final outOp = _bindings.malloc(WasmBindings.pointerSize);
    final outIndirect = _bindings.malloc(WasmBindings.pointerSize);

    final value = _bindings.sqlite3changeset_op(
        pointer, outTable, outColCount, outOp, outIndirect);

    final colCount = _bindings.memory.int32ValueOfPointer(outColCount);
    final op = _bindings.memory.int32ValueOfPointer(outOp);
    final indirect = _bindings.memory.int32ValueOfPointer(outIndirect);
    final rawTable = _bindings.memory.int32ValueOfPointer(outTable);
    final table = value == 0 ? _bindings.memory.readString(rawTable) : '';

    _bindings
      ..free(outTable)
      ..free(outColCount)
      ..free(outOp)
      ..free(outIndirect);

    if (value != 0) {
      throw createExceptionOutsideOfDatabase(bindings, value);
    }

    return RawChangeSetOp(
      tableName: table,
      columnCount: colCount,
      operation: op,
      indirect: indirect,
    );
  }
}
