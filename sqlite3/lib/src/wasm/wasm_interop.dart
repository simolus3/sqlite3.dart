// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import '../../wasm.dart';
import '../implementation/bindings.dart';
import 'bindings.dart';
import 'js_interop.dart';

import 'package:web/web.dart' as web;

import 'sqlite3_wasm.g.dart';

// ignore_for_file: non_constant_identifier_names

class WasmBindings {
  // We're compiling to 32bit wasm
  static const pointerSize = 4;

  final WasmInstance instance;
  final Memory memory;

  final DartCallbacks callbacks;
  final SqliteExports sqlite3;

  WasmBindings._(this.instance, _InjectedValues values)
      : memory = values.memory,
        callbacks = values.callbacks,
        sqlite3 = SqliteExports(instance.exports) {
    values.bindings = this;
  }

  static Future<WasmBindings> instantiateAsync(web.Response response) async {
    final injected = _InjectedValues();
    final instance = await WasmInstance.load(response, injected.injectedValues);

    return WasmBindings._(instance, injected);
  }

  JSFunction _checkForPresence(JSFunction? function, String name) {
    if (function == null) {
      throw UnsupportedError(
          '$name is not supported by WASM sqlite3, try upgrading to '
          'a more recent sqlite3.wasm');
    }

    return function;
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

  int sqlite3_initialize() {
    return switch (sqlite3.sqlite3_initialize) {
      final fun? => fun.callReturningInt0(),
      null => 0,
    };
  }

  int create_scalar_function(
      Pointer db, Pointer functionName, int nArg, int eTextRep, int id) {
    return sqlite3.dart_sqlite3_create_scalar_function(
        db, functionName, nArg, eTextRep, id);
  }

  int create_aggregate_function(
      Pointer db, Pointer functionName, int nArg, int eTextRep, int id) {
    return sqlite3.dart_sqlite3_create_aggregate_function(
        db, functionName, nArg, eTextRep, id);
  }

  int create_window_function(
      Pointer db, Pointer functionName, int nArg, int eTextRep, int id) {
    final function = _checkForPresence(
        sqlite3.dart_sqlite3_create_window_function, 'createWindow');
    return function.callReturningInt5(
        db.toJS, functionName.toJS, nArg.toJS, eTextRep.toJS, id.toJS);
  }

  int create_collation(Pointer db, Pointer name, int eTextRep, int id) {
    final function = _checkForPresence(
        sqlite3.dart_sqlite3_create_collation, 'createCollation');
    return function.callReturningInt4(
        db.toJS, name.toJS, eTextRep.toJS, id.toJS);
  }

  Pointer dart_sqlite3_register_vfs(Pointer name, int dartId, int makeDefault) {
    return sqlite3.dart_sqlite3_register_vfs(name, dartId, makeDefault);
  }

  int sqlite3_vfs_unregister(Pointer vfs) {
    return sqlite3.sqlite3_vfs_unregister(vfs);
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
    return sqlite3.sqlite3_error_offset?.callReturningInt(db.toJS) ?? -1;
  }

  int sqlite3_extended_result_codes(Pointer db, int onoff) {
    return sqlite3.sqlite3_extended_result_codes(db, onoff);
  }

  /// Pass a non-negative [id] to enable update tracking on the db, a negative
  /// one to stop it.
  void dart_sqlite3_updates(Pointer db, int id) {
    return sqlite3.dart_sqlite3_updates?.callReturningVoid2(db.toJS, id.toJS);
  }

  void dart_sqlite3_commits(Pointer db, int id) {
    return sqlite3.dart_sqlite3_commits?.callReturningVoid2(db.toJS, id.toJS);
  }

  void dart_sqlite3_rollbacks(Pointer db, int id) {
    return sqlite3.dart_sqlite3_rollbacks?.callReturningVoid2(db.toJS, id.toJS);
  }

  int sqlite3_exec(Pointer db, Pointer sql, Pointer callback,
      Pointer callbackArg, Pointer errorOut) {
    return sqlite3.sqlite3_exec(db, sql, callback, callbackArg, errorOut);
  }

  int sqlite3_prepare_v3(Pointer db, Pointer sql, int length, int prepFlags,
      Pointer ppStmt, Pointer pzTail) {
    return sqlite3.sqlite3_prepare_v3(
        db, sql, length, prepFlags, ppStmt, pzTail);
  }

  int sqlite3_bind_parameter_count(Pointer stmt) {
    return sqlite3.sqlite3_bind_parameter_count(stmt);
  }

  int sqlite3_bind_null(Pointer stmt, int index) {
    return sqlite3.sqlite3_bind_null(stmt, index);
  }

  int sqlite3_bind_int64(Pointer stmt, int index, BigInt value) {
    return sqlite3.sqlite3_bind_int64(
        stmt, index, JsBigInt.fromBigInt(value).jsObject);
  }

  int sqlite3_bind_int(Pointer stmt, int index, int value) {
    return sqlite3.sqlite3_bind_int64(
        stmt, index, JsBigInt.fromInt(value).jsObject);
  }

  int sqlite3_bind_double(Pointer stmt, int index, double value) {
    return sqlite3.sqlite3_bind_double(stmt, index, value);
  }

  int sqlite3_bind_text(
      Pointer stmt, int index, Pointer text, int length, Pointer a) {
    return sqlite3.sqlite3_bind_text(stmt, index, text, length, a);
  }

  int sqlite3_bind_blob64(
      Pointer stmt, int index, Pointer test, int length, Pointer a) {
    return sqlite3.sqlite3_bind_blob64(
        stmt, index, test, JsBigInt.fromInt(length), a);
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
    return sqlite3.sqlite3_value_subtype?.callReturningInt(value.toJS) ?? 0;
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
      Pointer context, Pointer text, int length, Pointer a) {
    sqlite3.sqlite3_result_text(context, text, length, a);
  }

  void sqlite3_result_blob64(
      Pointer context, Pointer blob, int length, Pointer a) {
    sqlite3.sqlite3_result_blob64(context, blob, JsBigInt.fromInt(length), a);
  }

  void sqlite3_result_error(Pointer context, Pointer text, int length) {
    sqlite3.sqlite3_result_error(context, text, length);
  }

  void sqlite3_result_subtype(Pointer context, int subtype) {
    sqlite3.sqlite3_result_subtype
        ?.callReturningVoid2(context.toJS, subtype.toJS);
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
    final function = sqlite3.dart_sqlite3_db_config_int;
    if (function != null) {
      return function.callReturningInt3(db.toJS, op.toJS, value.toJS);
    } else {
      return 1; // Not supported with this wasm build
    }
  }

  int sqlite3session_create(Pointer db, Pointer zDb, Pointer sessionOut) {
    return sqlite3.sqlite3session_create!
        .callReturningInt3(db.toJS, zDb.toJS, sessionOut.toJS);
  }

  void sqlite3session_delete(Pointer session) {
    sqlite3.sqlite3session_delete!.callAsFunction(null, session.toJS);
  }

  int sqlite3session_enable(Pointer session, int enable) {
    return sqlite3.sqlite3session_enable!
        .callReturningInt2(session.toJS, enable.toJS);
  }

  int sqlite3session_indirect(Pointer session, int enable) {
    return sqlite3.sqlite3session_indirect!
        .callReturningInt2(session.toJS, enable.toJS);
  }

  int sqlite3session_isempty(Pointer session) {
    return sqlite3.sqlite3session_isempty!.callReturningInt(session.toJS);
  }

  int sqlite3session_attach(Pointer session, Pointer zTab) {
    return sqlite3.sqlite3session_attach!
        .callReturningInt2(session.toJS, zTab.toJS);
  }

  int sqlite3session_diff(
      Pointer session, Pointer zFromDb, Pointer zTbl, Pointer pzErrMsg) {
    return sqlite3.sqlite3session_diff!.callReturningInt4(
        session.toJS, zFromDb.toJS, zTbl.toJS, pzErrMsg.toJS);
  }

  int sqlite3session_patchset(
      Pointer session, Pointer pnPatchset, Pointer ppPatchset) {
    return sqlite3.sqlite3session_patchset!
        .callReturningInt3(session.toJS, pnPatchset.toJS, ppPatchset.toJS);
  }

  int sqlite3session_changeset(
      Pointer session, Pointer pnPatchset, Pointer ppPatchset) {
    return sqlite3.sqlite3session_changeset!
        .callReturningInt3(session.toJS, pnPatchset.toJS, ppPatchset.toJS);
  }

  int sqlite3changeset_invert(
      int nIn, Pointer pIn, Pointer pnOut, Pointer ppOut) {
    return sqlite3.sqlite3changeset_invert!
        .callReturningInt4(nIn.toJS, pIn.toJS, pnOut.toJS, ppOut.toJS);
  }

  int sqlite3changeset_start(Pointer outPtr, int size, Pointer changeset) {
    return sqlite3.sqlite3changeset_start!
        .callReturningInt3(outPtr.toJS, size.toJS, changeset.toJS);
  }

  int sqlite3changeset_finalize(Pointer iterator) {
    return sqlite3.sqlite3changeset_finalize!.callReturningInt(iterator.toJS);
  }

  int sqlite3changeset_next(Pointer iterator) {
    return sqlite3.sqlite3changeset_next!.callReturningInt(iterator.toJS);
  }

  int sqlite3changeset_op(Pointer iterator, Pointer outTable,
      Pointer outColCount, Pointer outOp, Pointer outIndirect) {
    return sqlite3.sqlite3changeset_op!.callReturningInt5(iterator.toJS,
        outTable.toJS, outColCount.toJS, outOp.toJS, outIndirect.toJS);
  }

  int sqlite3changeset_old(Pointer iterator, int iVal, Pointer outValue) {
    return sqlite3.sqlite3changeset_old!
        .callReturningInt3(iterator.toJS, iVal.toJS, outValue.toJS);
  }

  int sqlite3changeset_new(Pointer iterator, int iVal, Pointer outValue) {
    return sqlite3.sqlite3changeset_new!
        .callReturningInt3(iterator.toJS, iVal.toJS, outValue.toJS);
  }

  int dart_sqlite3changeset_apply(
      Pointer db, int length, Pointer changeset, Pointer context, int filter) {
    return sqlite3.dart_sqlite3changeset_apply!.callReturningInt5(
        db.toJS, length.toJS, changeset.toJS, context.toJS, filter.toJS);
  }

  Pointer get sqlite3_temp_directory {
    return sqlite3.sqlite3_temp_directory.value.toDartInt;
  }

  set sqlite3_temp_directory(Pointer value) {
    sqlite3.sqlite3_temp_directory.value = value.toJS;
  }
}

int _runVfs(void Function() body) {
  try {
    body();
    return SqlError.SQLITE_OK;
  } on VfsException catch (e) {
    return e.returnCode;
  } on Object {
    return SqlError.SQLITE_ERROR;
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
    return utf8
        .decode(dartBuffer.asUint8List(address, length ?? strlen(address)));
  }

  String? readNullableString(int address, [int? length]) {
    if (address == 0) return null;

    return utf8
        .decode(dartBuffer.asUint8List(address, length ?? strlen(address)));
  }

  Uint8List copyRange(Pointer pointer, int length) {
    final list = Uint8List(length);
    list.setAll(0, dartBuffer.asUint8List(pointer, length));
    return list;
  }
}

class _InjectedValues {
  late WasmBindings bindings;
  late Map<String, Map<String, JSObject>> injectedValues;

  late Memory memory;

  final DartCallbacks callbacks = DartCallbacks();

  _InjectedValues() {
    final memory = this.memory = Memory(MemoryDescriptor(initial: 16.toJS));

    injectedValues = {
      'env': {'memory': memory},
      'dart': {
        // See assets/wasm/bridge.h
        'error_log': ((Pointer ptr) {
          print('[sqlite3] ${memory.readString(ptr)}');
        }).toJS,
        'xOpen': ((int vfsId, Pointer zName, Pointer dartFdPtr, int flags,
            Pointer pOutFlags) {
          final vfs = callbacks.registeredVfs[vfsId]!;
          final path = Sqlite3Filename(memory.readNullableString(zName));

          return _runVfs(() {
            final result = vfs.xOpen(path, flags);
            final fd = callbacks.registerFile(result.file);

            memory.setInt32Value(dartFdPtr, fd);
            if (pOutFlags != 0) {
              memory.setInt32Value(pOutFlags, result.outFlags);
            }
          });
        }).toJS,
        'xDelete': ((int vfsId, Pointer zName, int syncDir) {
          final vfs = callbacks.registeredVfs[vfsId]!;
          final path = memory.readString(zName);

          return _runVfs(() => vfs.xDelete(path, syncDir));
        }).toJS,
        'xAccess': ((int vfsId, Pointer zName, int flags, Pointer pResOut) {
          final vfs = callbacks.registeredVfs[vfsId]!;
          final path = memory.readString(zName);

          return _runVfs(() {
            final res = vfs.xAccess(path, flags);
            memory.setInt32Value(pResOut, res);
          });
        }).toJS,
        'xFullPathname': ((int vfsId, Pointer zName, int nOut, Pointer zOut) {
          final vfs = callbacks.registeredVfs[vfsId]!;
          final path = memory.readString(zName);

          return _runVfs(() {
            final fullPath = vfs.xFullPathName(path);
            final encoded = utf8.encode(fullPath);

            if (encoded.length > nOut) {
              throw VfsException(SqlError.SQLITE_CANTOPEN);
            }

            memory.asBytes
              ..setAll(zOut, encoded)
              ..[zOut + encoded.length] = 0;
          });
        }).toJS,
        'xRandomness': ((int vfsId, int nByte, Pointer zOut) {
          final vfs = callbacks.registeredVfs[vfsId];

          return _runVfs(() {
            final target = memory.buffer.toDart.asUint8List(zOut, nByte);

            if (vfs != null) {
              vfs.xRandomness(target);
            } else {
              // Fall back to a default random source. We're using this to
              // implement `getentropy` in C which is used by sqlite3mc.
              return BaseVirtualFileSystem.generateRandomness(target);
            }
          });
        }).toJS,
        'xSleep': ((int vfsId, int micros) {
          final vfs = callbacks.registeredVfs[vfsId]!;

          return _runVfs(() {
            vfs.xSleep(Duration(microseconds: micros));
          });
        }).toJS,
        'xCurrentTimeInt64': ((int vfsId, Pointer target) {
          final vfs = callbacks.registeredVfs[vfsId]!;
          final time = vfs.xCurrentTime();

          // dartvfs_currentTimeInt64 will turn this into the right value, it's
          // annoying to do in JS due to the lack of proper ints.
          memory.setInt64Value(
              target, JsBigInt.fromInt(time.millisecondsSinceEpoch));
        }).toJS,
        'xDeviceCharacteristics': ((int fd) {
          final file = callbacks.openedFiles[fd]!;
          return file.xDeviceCharacteristics;
        }).toJS,
        'xClose': ((int fd) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() {
            file.xClose();
            callbacks.openedFiles.remove(fd);
          });
        }).toJS,
        'xRead': ((int fd, Pointer target, int amount, JSBigInt offset) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() {
            file.xRead(memory.buffer.toDart.asUint8List(target, amount),
                JsBigInt(offset).asDartInt);
          });
        }).toJS,
        'xWrite': ((int fd, Pointer source, int amount, JSBigInt offset) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() {
            file.xWrite(memory.buffer.toDart.asUint8List(source, amount),
                JsBigInt(offset).asDartInt);
          });
        }).toJS,
        'xTruncate': ((int fd, JSBigInt size) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() => file.xTruncate(JsBigInt(size).asDartInt));
        }).toJS,
        'xSync': ((int fd, int flags) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() => file.xSync(flags));
        }).toJS,
        'xFileSize': ((int fd, Pointer sizePtr) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() {
            final size = file.xFileSize();
            memory.setInt32Value(sizePtr, size);
          });
        }).toJS,
        'xLock': ((int fd, int flags) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() => file.xLock(flags));
        }).toJS,
        'xUnlock': ((int fd, int flags) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() => file.xUnlock(flags));
        }).toJS,
        'xCheckReservedLock': ((int fd, Pointer pResOut) {
          final file = callbacks.openedFiles[fd]!;
          return _runVfs(() {
            final status = file.xCheckReservedLock();
            memory.setInt32Value(pResOut, status);
          });
        }).toJS,
        'function_xFunc': ((Pointer ctx, int args, Pointer value) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks.functions[id]!.xFunc!(
            WasmContext(bindings, ctx, callbacks),
            WasmValueList(bindings, args, value),
          );
        }).toJS,
        'function_xStep': ((Pointer ctx, int args, Pointer value) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks.functions[id]!.xStep!(
            WasmContext(bindings, ctx, callbacks),
            WasmValueList(bindings, args, value),
          );
        }).toJS,
        'function_xInverse': ((Pointer ctx, int args, Pointer value) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks.functions[id]!.xInverse!(
            WasmContext(bindings, ctx, callbacks),
            WasmValueList(bindings, args, value),
          );
        }).toJS,
        'function_xFinal': ((Pointer ctx) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks
              .functions[id]!.xFinal!(WasmContext(bindings, ctx, callbacks));
        }).toJS,
        'function_xValue': ((Pointer ctx) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks
              .functions[id]!.xValue!(WasmContext(bindings, ctx, callbacks));
        }).toJS,
        'function_forget': ((Pointer ctx) {
          callbacks.forget(ctx);
        }).toJS,
        'function_compare':
            ((Pointer ctx, int lengthA, Pointer a, int lengthB, int b) {
          final aStr = memory.readNullableString(a, lengthA);
          final bStr = memory.readNullableString(b, lengthB);

          return callbacks.functions[ctx]!.collation!(aStr, bStr);
        }).toJS,
        'function_hook':
            ((int id, int kind, Pointer _, Pointer table, JSBigInt rowId) {
          final tableName = memory.readString(table);

          callbacks.installedUpdateHook
              ?.call(kind, tableName, JsBigInt(rowId).asDartInt);
        }).toJS,
        'function_commit_hook': ((int id) {
          return callbacks.installedCommitHook?.call();
        }).toJS,
        'function_rollback_hook': ((int id) {
          callbacks.installedRollbackHook?.call();
        }).toJS,
        'localtime': ((JsBigInt timestamp, int resultPtr) {
          // struct tm {
          // 	int tm_sec;
          // 	int tm_min;
          // 	int tm_hour;
          // 	int tm_mday;
          // 	int tm_mon;
          // 	int tm_year; // With 0 representing 1900
          // 	int tm_wday;
          // 	int tm_yday;
          // 	int tm_isdst;
          // 	long __tm_gmtoff;
          // 	const char *__tm_zone; // Set by native helper
          // };
          final time = timestamp.asDartInt * 1000;
          final dateTime = DateTime.fromMillisecondsSinceEpoch(time);

          final tmValues = memory.buffer.toDart.asUint32List(resultPtr, 8);
          tmValues[0] = dateTime.second;
          tmValues[1] = dateTime.minute;
          tmValues[2] = dateTime.hour;
          tmValues[3] = dateTime.day;
          tmValues[4] = dateTime.month - 1;
          tmValues[5] = dateTime.year - 1900;
          // In Dart, the range is Monday=1 to Sunday=7. We want Sunday = 0 and
          // Saturday = 6.
          tmValues[6] = dateTime.weekday % 7;
          // yday not used by sqlite3, what could possibly go wrong by us not
          // setting that field (at least we have tests for this).
          // the other fields don't matter though, localtime_r is not supposed
          // to set them.
        }).toJS,
        'changeset_apply_filter': (Pointer context, Pointer zTab) {
          final cb = callbacks.sessionApply[context]!;
          return cb.filter!(zTab);
        }.toJS,
        'changeset_apply_conflict':
            (Pointer context, int eConflict, Pointer iter) {
          final cb = callbacks.sessionApply[context]!;
          return cb.conflict!(eConflict, iter);
        }.toJS,
      }
    };
  }
}

class DartCallbacks {
  int _id = 0;
  final Map<int, RegisteredFunctionSet> functions = {};

  int aggregateContextId = 1;
  final Map<int, AggregateContext<Object?>> aggregateContexts = {};

  final Map<int, VirtualFileSystem> registeredVfs = {};
  final Map<int, VirtualFileSystemFile> openedFiles = {};
  final Map<int, SessionApplyCallbacks> sessionApply = {};

  RawUpdateHook? installedUpdateHook;
  RawCommitHook? installedCommitHook;
  RawRollbackHook? installedRollbackHook;

  int register(RegisteredFunctionSet set) {
    final id = _id++;
    functions[id] = set;
    return id;
  }

  int registerVfs(VirtualFileSystem vfs) {
    final id = _id++;
    registeredVfs[id] = vfs;
    return id;
  }

  int registerFile(VirtualFileSystemFile file) {
    final id = _id++;
    openedFiles[id] = file;
    return id;
  }

  int registerChangesetApply(SessionApplyCallbacks cb) {
    final id = _id++;
    sessionApply[id] = cb;
    return id;
  }

  void forget(int id) => functions.remove(id);

  static final sqliteVfsPointer = Expando<int>();
}

class RegisteredFunctionSet {
  final RawXFunc? xFunc;
  final RawXStep? xStep;
  final RawXFinal? xFinal;

  final RawXFinal? xValue;
  final RawXStep? xInverse;

  final RawCollation? collation;

  RegisteredFunctionSet({
    this.xFunc,
    this.xStep,
    this.xFinal,
    this.xValue,
    this.xInverse,
    this.collation,
  });
}

typedef RawFilter = int Function(Pointer tableName);

typedef RawConflict = int Function(int eConflict, Pointer iterator);

final class SessionApplyCallbacks {
  final RawFilter? filter;
  final RawConflict? conflict;

  SessionApplyCallbacks(this.filter, this.conflict);
}

extension on JSFunction {
  @JS('call')
  external JSNumber _call5(
      JSAny? r, JSAny? a0, JSAny? a1, JSAny? a2, JSAny? a3, JSAny? a4);

  int callReturningInt0() {
    return (callAsFunction(null) as JSNumber).toDartInt;
  }

  int callReturningInt(JSAny? arg) {
    return (callAsFunction(null, arg) as JSNumber).toDartInt;
  }

  int callReturningInt2(JSAny? arg0, JSAny? arg1) {
    return (callAsFunction(null, arg0, arg1) as JSNumber).toDartInt;
  }

  int callReturningInt3(JSAny? arg0, JSAny? arg1, JSAny? arg2) {
    return (callAsFunction(null, arg0, arg1, arg2) as JSNumber).toDartInt;
  }

  int callReturningInt4(JSAny? arg0, JSAny? arg1, JSAny? arg2, JSAny? arg3) {
    return (callAsFunction(null, arg0, arg1, arg2, arg3) as JSNumber).toDartInt;
  }

  int callReturningInt5(
      JSAny? arg0, JSAny? arg1, JSAny? arg2, JSAny? arg3, JSAny? arg4) {
    return _call5(null, arg0, arg1, arg2, arg3, arg4).toDartInt;
  }

  void callReturningVoid2(JSAny? arg0, JSAny? arg1) {
    callAsFunction(null, arg0, arg1);
  }
}
