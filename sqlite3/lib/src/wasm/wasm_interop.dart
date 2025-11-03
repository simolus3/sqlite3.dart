// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import '../implementation/bindings.dart';
import 'injected_values.dart';
import 'js_interop.dart';

import 'package:web/web.dart' as web;

import 'sqlite3_wasm.g.dart';

// ignore_for_file: non_constant_identifier_names

class WasmBindings {
  // We're compiling to 32bit wasm
  static const pointerSize = 4;

  final WasmInstance instance;
  final Memory memory;

  final DartBridgeCallbacks callbacks;
  final SqliteExports sqlite3;

  // Finalizers are deliberately referenced from this instance only - if the
  // entire instance and module is GCed, we don't need to manually invoke
  // finalizers anymore.
  Finalizer<Pointer>? changesetFinalizer,
      sessionFinalizer,
      databaseFinalizer,
      statementFinalizer;

  WasmBindings._(this.instance, this.callbacks)
    : memory = callbacks.memory,
      sqlite3 = SqliteExports(instance.exports) {
    callbacks.bindings = this;

    changesetFinalizer = Finalizer((p) => sqlite3.sqlite3changeset_finalize(p));
    sessionFinalizer = Finalizer((p) => sqlite3.sqlite3session_delete(p));
    databaseFinalizer = Finalizer((p) => sqlite3.sqlite3_close_v2(p));
    statementFinalizer = Finalizer((p) => sqlite3.sqlite3_finalize(p));
  }

  static Future<WasmBindings> instantiateAsync(web.Response response) async {
    final memory = Memory(MemoryDescriptor(initial: 16.toJS));
    final injectedDartFunctions = DartBridgeCallbacks(memory);

    final imported = JSObject();
    imported['env'] = JSObject()..['memory'] = memory;
    imported['dart'] = createJSInteropWrapper(injectedDartFunctions);

    final instance = await WasmInstance.load(response, imported);
    return WasmBindings._(instance, injectedDartFunctions);
  }

  Pointer allocateBytes(List<int> bytes, {int additionalLength = 0}) {
    final ptr = malloc(bytes.length + additionalLength);
    memory.asBytes
      ..setRange(ptr, ptr + bytes.length, bytes)
      ..fillRange(ptr + bytes.length, ptr + bytes.length + additionalLength, 0);

    return ptr;
  }

  Pointer allocateZeroTerminated(String string) {
    return allocateBytes(utf8.encode(string), additionalLength: 1);
  }

  Pointer malloc(int size) {
    return sqlite3.dart_sqlite3_malloc(size);
  }

  void free(Pointer pointer) {
    sqlite3.dart_sqlite3_free(pointer);
  }

  void sqlite3_free(Pointer ptr) => sqlite3.sqlite3_free(ptr);

  int sqlite3_initialize() => sqlite3.sqlite3_initialize();

  int create_window_function(
    Pointer db,
    Pointer functionName,
    int nArg,
    int eTextRep,
    RegisteredFunctionSet set,
  ) {
    return sqlite3.dart_sqlite3_create_window_function(
      db,
      functionName,
      nArg,
      eTextRep,
      set.toExternalReference,
    );
  }

  int sqlite3_vfs_unregister(Pointer vfs) {
    return sqlite3.dart_sqlite3_unregister_vfs(vfs);
  }

  int sqlite3_libversion() => sqlite3.sqlite3_libversion();

  Pointer sqlite3_sourceid() => sqlite3.sqlite3_sourceid();

  int sqlite3_libversion_number() => sqlite3.sqlite3_libversion_number();

  int sqlite3_open_v2(Pointer filename, Pointer ppDb, int flags, Pointer zVfs) {
    return sqlite3.sqlite3_open_v2(filename, ppDb, flags, zVfs);
  }

  int sqlite3_close_v2(Pointer db) => sqlite3.sqlite3_close_v2(db);

  int sqlite3_extended_errcode(Pointer db) =>
      sqlite3.sqlite3_extended_errcode(db);

  Pointer sqlite3_errmsg(Pointer db) => sqlite3.sqlite3_errmsg(db);

  Pointer sqlite3_errstr(int resultCode) => sqlite3.sqlite3_errstr(resultCode);

  int sqlite3_error_offset(Pointer db) {
    return sqlite3.sqlite3_error_offset(db);
  }

  int sqlite3_extended_result_codes(Pointer db, int onoff) {
    return sqlite3.sqlite3_extended_result_codes(db, onoff);
  }

  /// Pass a non-negative [id] to enable update tracking on the db, a negative
  /// one to stop it.
  void dart_sqlite3_updates(Pointer db, RawUpdateHook? hook) {
    return sqlite3.dart_sqlite3_updates(db, hook?.toExternalReference);
  }

  void dart_sqlite3_commits(Pointer db, RawCommitHook? hook) {
    return sqlite3.dart_sqlite3_commits(db, hook?.toExternalReference);
  }

  void dart_sqlite3_rollbacks(Pointer db, RawRollbackHook? rollback) {
    return sqlite3.dart_sqlite3_rollbacks(db, rollback?.toExternalReference);
  }

  int sqlite3_exec(
    Pointer db,
    Pointer sql,
    Pointer callback,
    Pointer callbackArg,
    Pointer errorOut,
  ) {
    return sqlite3.sqlite3_exec(db, sql, callback, callbackArg, errorOut);
  }

  int sqlite3_prepare_v3(
    Pointer db,
    Pointer sql,
    int length,
    int prepFlags,
    Pointer ppStmt,
    Pointer pzTail,
  ) {
    return sqlite3.sqlite3_prepare_v3(
      db,
      sql,
      length,
      prepFlags,
      ppStmt,
      pzTail,
    );
  }

  int sqlite3_bind_parameter_count(Pointer stmt) {
    return sqlite3.sqlite3_bind_parameter_count(stmt);
  }

  int sqlite3_bind_null(Pointer stmt, int index) {
    return sqlite3.sqlite3_bind_null(stmt, index);
  }

  int sqlite3_bind_int64(Pointer stmt, int index, BigInt value) {
    return sqlite3.sqlite3_bind_int64(
      stmt,
      index,
      JsBigInt.fromBigInt(value).jsObject,
    );
  }

  int sqlite3_bind_int(Pointer stmt, int index, int value) {
    return sqlite3.sqlite3_bind_int64(
      stmt,
      index,
      JsBigInt.fromInt(value).jsObject,
    );
  }

  int sqlite3_bind_double(Pointer stmt, int index, double value) {
    return sqlite3.sqlite3_bind_double(stmt, index, value);
  }

  /// Calls `sqlite3_bind_text` with `free` as the destructor argument.
  int sqlite3_bind_text_finalizerFree(
    Pointer stmt,
    int index,
    Pointer text,
    int length,
  ) {
    return sqlite3.dart_sqlite3_bind_text(stmt, index, text, length);
  }

  /// Calls `sqlite3_bind_blob` with `free` as the destructor argument.
  int sqlite3_bind_blob_finalizerFree(
    Pointer stmt,
    int index,
    Pointer test,
    int length,
  ) {
    return sqlite3.dart_sqlite3_bind_blob(stmt, index, test, length);
  }

  int sqlite3_bind_parameter_index(Pointer statement, Pointer key) {
    return sqlite3.sqlite3_bind_parameter_index(statement, key);
  }

  int sqlite3_column_count(Pointer stmt) {
    return sqlite3.sqlite3_column_count(stmt);
  }

  Pointer sqlite3_column_name(Pointer stmt, int index) {
    return sqlite3.sqlite3_column_name(stmt, index);
  }

  int sqlite3_column_type(Pointer stmt, int index) {
    return sqlite3.sqlite3_column_type(stmt, index);
  }

  JsBigInt sqlite3_column_int64(Pointer stmt, int index) {
    return JsBigInt(sqlite3.sqlite3_column_int64(stmt, index));
  }

  double sqlite3_column_double(Pointer stmt, int index) {
    return sqlite3.sqlite3_column_double(stmt, index);
  }

  int sqlite3_column_bytes(Pointer stmt, int index) {
    return sqlite3.sqlite3_column_bytes(stmt, index);
  }

  Pointer sqlite3_column_text(Pointer stmt, int index) {
    return sqlite3.sqlite3_column_text(stmt, index);
  }

  Pointer sqlite3_column_blob(Pointer stmt, int index) {
    return sqlite3.sqlite3_column_blob(stmt, index);
  }

  int sqlite3_value_type(Pointer value) {
    return sqlite3.sqlite3_value_type(value);
  }

  int sqlite3_value_subtype(Pointer value) {
    return sqlite3.sqlite3_value_subtype(value);
  }

  JsBigInt sqlite3_value_int64(Pointer value) {
    return JsBigInt(sqlite3.sqlite3_value_int64(value));
  }

  double sqlite3_value_double(Pointer value) {
    return sqlite3.sqlite3_value_double(value);
  }

  int sqlite3_value_bytes(Pointer value) {
    return sqlite3.sqlite3_value_bytes(value);
  }

  Pointer sqlite3_value_text(Pointer value) {
    return sqlite3.sqlite3_value_text(value);
  }

  Pointer sqlite3_value_blob(Pointer value) {
    return sqlite3.sqlite3_value_blob(value);
  }

  void sqlite3_result_null(Pointer context) {
    sqlite3.sqlite3_result_null(context);
  }

  void sqlite3_result_int64(Pointer context, BigInt value) {
    sqlite3.sqlite3_result_int64(context, JsBigInt.fromBigInt(value).jsObject);
  }

  void sqlite3_result_double(Pointer context, double value) {
    sqlite3.sqlite3_result_double(context, value);
  }

  void sqlite3_result_text(
    Pointer context,
    Pointer text,
    int length,
    Pointer a,
  ) {
    sqlite3.sqlite3_result_text(context, text, length, a);
  }

  void sqlite3_result_blob64(
    Pointer context,
    Pointer blob,
    int length,
    Pointer a,
  ) {
    sqlite3.sqlite3_result_blob64(context, blob, JsBigInt.fromInt(length), a);
  }

  void sqlite3_result_error(Pointer context, Pointer text, int length) {
    sqlite3.sqlite3_result_error(context, text, length);
  }

  void sqlite3_result_subtype(Pointer context, int subtype) {
    sqlite3.sqlite3_result_subtype(context, subtype);
  }

  int sqlite3_user_data(Pointer context) {
    return sqlite3.sqlite3_user_data(context);
  }

  Pointer sqlite3_aggregate_context(Pointer context, int nBytes) {
    return sqlite3.sqlite3_aggregate_context(context, nBytes);
  }

  int sqlite3_step(Pointer stmt) => sqlite3.sqlite3_step(stmt);

  int sqlite3_reset(Pointer stmt) => sqlite3.sqlite3_reset(stmt);

  int sqlite3_finalize(Pointer stmt) => sqlite3.sqlite3_finalize(stmt);

  int sqlite3_changes(Pointer db) => sqlite3.sqlite3_changes(db);

  int sqlite3_stmt_isexplain(Pointer stmt) =>
      sqlite3.sqlite3_stmt_isexplain(stmt);

  int sqlite3_stmt_readonly(Pointer stmt) =>
      sqlite3.sqlite3_stmt_readonly(stmt);

  int sqlite3_last_insert_rowid(Pointer db) =>
      JsBigInt(sqlite3.sqlite3_last_insert_rowid(db)).asDartInt;

  int sqlite3_get_autocommit(Pointer db) => sqlite3.sqlite3_get_autocommit(db);

  int sqlite3_db_config(Pointer db, int op, int value) {
    return sqlite3.dart_sqlite3_db_config_int(db, op, value);
  }

  int sqlite3session_create(Pointer db, Pointer zDb, Pointer sessionOut) {
    return sqlite3.sqlite3session_create(db, zDb, sessionOut);
  }

  void sqlite3session_delete(Pointer session) {
    sqlite3.sqlite3session_delete(session);
  }

  int sqlite3session_enable(Pointer session, int enable) {
    return sqlite3.sqlite3session_enable(session, enable);
  }

  int sqlite3session_indirect(Pointer session, int enable) {
    return sqlite3.sqlite3session_indirect(session, enable);
  }

  int sqlite3session_isempty(Pointer session) {
    return sqlite3.sqlite3session_isempty(session);
  }

  int sqlite3session_attach(Pointer session, Pointer zTab) {
    return sqlite3.sqlite3session_attach(session, zTab);
  }

  int sqlite3session_diff(
    Pointer session,
    Pointer zFromDb,
    Pointer zTbl,
    Pointer pzErrMsg,
  ) {
    return sqlite3.sqlite3session_diff(session, zFromDb, zTbl, pzErrMsg);
  }

  int sqlite3session_patchset(
    Pointer session,
    Pointer pnPatchset,
    Pointer ppPatchset,
  ) {
    return sqlite3.sqlite3session_patchset(session, pnPatchset, ppPatchset);
  }

  int sqlite3session_changeset(
    Pointer session,
    Pointer pnPatchset,
    Pointer ppPatchset,
  ) {
    return sqlite3.sqlite3session_changeset(session, pnPatchset, ppPatchset);
  }

  int sqlite3changeset_invert(
    int nIn,
    Pointer pIn,
    Pointer pnOut,
    Pointer ppOut,
  ) {
    return sqlite3.sqlite3changeset_invert(nIn, pIn, pnOut, ppOut);
  }

  int sqlite3changeset_start(Pointer outPtr, int size, Pointer changeset) {
    return sqlite3.sqlite3changeset_start(outPtr, size, changeset);
  }

  int sqlite3changeset_finalize(Pointer iterator) {
    return sqlite3.sqlite3changeset_finalize(iterator);
  }

  int sqlite3changeset_next(Pointer iterator) {
    return sqlite3.sqlite3changeset_next(iterator);
  }

  int sqlite3changeset_op(
    Pointer iterator,
    Pointer outTable,
    Pointer outColCount,
    Pointer outOp,
    Pointer outIndirect,
  ) {
    return sqlite3.sqlite3changeset_op(
      iterator,
      outTable,
      outColCount,
      outOp,
      outIndirect,
    );
  }

  int sqlite3changeset_old(Pointer iterator, int iVal, Pointer outValue) {
    return sqlite3.sqlite3changeset_old(iterator, iVal, outValue);
  }

  int sqlite3changeset_new(Pointer iterator, int iVal, Pointer outValue) {
    return sqlite3.sqlite3changeset_new(iterator, iVal, outValue);
  }

  Pointer get sqlite3_temp_directory {
    return sqlite3.sqlite3_temp_directory.value.toDartInt;
  }

  set sqlite3_temp_directory(Pointer value) {
    sqlite3.sqlite3_temp_directory.value = value.toJS;
  }
}

extension WrappedMemory on Memory {
  ByteBuffer get dartBuffer => buffer.toDart;

  Uint8List get asBytes => buffer.toDart.asUint8List();

  int strlen(int address) {
    assert(address != 0, 'Null pointer dereference');

    final bytes = dartBuffer.asUint8List(address);

    var length = 0;
    while (bytes[length] != 0) {
      length++;
    }

    return length;
  }

  int int32ValueOfPointer(Pointer pointer) {
    assert(pointer != 0, 'Null pointer dereference');
    return dartBuffer.asInt32List()[pointer >> 2];
  }

  void setInt32Value(Pointer pointer, int value) {
    assert(pointer != 0, 'Null pointer dereference');
    dartBuffer.asInt32List()[pointer >> 2] = value;
  }

  void setInt64Value(Pointer pointer, JsBigInt value) {
    assert(pointer != 0, 'Null pointer dereference');
    dartBuffer.asByteData().setBigInt64(pointer, value, true);
  }

  String readString(int address, [int? length]) {
    assert(address != 0, 'Null pointer dereference');
    return utf8.decode(
      dartBuffer.asUint8List(address, length ?? strlen(address)),
    );
  }

  String? readNullableString(int address, [int? length]) {
    if (address == 0) return null;

    return utf8.decode(
      dartBuffer.asUint8List(address, length ?? strlen(address)),
    );
  }

  Uint8List copyRange(Pointer pointer, int length) {
    final list = Uint8List(length);
    list.setAll(0, dartBuffer.asUint8List(pointer, length));
    return list;
  }
}

// 'changeset_apply_filter': (Pointer context, Pointer zTab) {
//           final cb = callbacks.sessionApply[context]!;
//           return cb.filter!(zTab);
//         }.toJS,
//         'changeset_apply_conflict':
//             (Pointer context, int eConflict, Pointer iter) {
//               final cb = callbacks.sessionApply[context]!;
//               return cb.conflict!(eConflict, iter);
//             }.toJS,

// class DartCallbacks {
//   int _id = 0;

//   int aggregateContextId = 1;
//   final Map<int, AggregateContext<Object?>> aggregateContexts = {};

//
// }

typedef RawFilter = int Function(Pointer tableName);

typedef RawConflict = int Function(int eConflict, Pointer iterator);
