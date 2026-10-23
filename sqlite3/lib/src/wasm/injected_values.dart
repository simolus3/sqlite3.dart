// Dart functions that are injected into the SQLite WebAssembly module. For
// details, see sqlite3_wasm_build/bridge.h

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart';

import '../constants.dart';
import '../functions.dart';
import '../implementation/bindings.dart';
import '../session.dart';
import '../vfs.dart';
import 'bindings.dart';
import 'js_interop.dart';
import 'sqlite3_wasm.g.dart';
import 'wasm_interop.dart';

final class DartBridgeCallbacks {
  // We only have access to bindings and memory after instantiating the module.
  late final WasmBindings bindings;
  late final Memory memory;

  int aggregateContextId = 1;
  // TODO: Remove from this map eventually?
  final Map<int, AggregateContext<Object?>> aggregateContexts = {};

  @JSExport('error_log')
  void logError(Pointer message) {
    print('[sqlite3] ${memory.readString(message)}');
  }

  @JSExport()
  void localtime(JsBigInt timestamp, int resultPtr) {
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
  }

  @JSExport()
  ExternalDartReference<VirtualFileSystemFile>? xOpen(
    ExternalDartReference<VirtualFileSystem> vfs,
    Pointer zName,
    Pointer rcPtr,
    int flags,
    Pointer pOutFlags,
  ) {
    try {
      final path = Sqlite3Filename(memory.readNullableString(zName));

      final result = vfs.toDartObject.xOpen(path, flags);
      if (pOutFlags != 0) {
        memory.setInt32Value(pOutFlags, result.outFlags);
      }

      memory.setInt32Value(rcPtr, 0);
      return result.file.toExternalReference;
    } on VfsException catch (e) {
      memory.setInt32Value(rcPtr, e.returnCode);
    } on Object {
      memory.setInt32Value(rcPtr, SqlError.SQLITE_ERROR);
    }

    return null;
  }

  @JSExport()
  int xDelete(
    ExternalDartReference<VirtualFileSystem> vfs,
    Pointer zName,
    int syncDir,
  ) {
    return _runVfs(() {
      final path = memory.readString(zName);
      vfs.toDartObject.xDelete(path, syncDir);
    });
  }

  @JSExport()
  int xAccess(
    ExternalDartReference<VirtualFileSystem> vfs,
    Pointer zName,
    int flags,
    Pointer pResOut,
  ) {
    return _runVfs(() {
      final path = memory.readString(zName);
      final res = vfs.toDartObject.xAccess(path, flags);
      memory.setInt32Value(pResOut, res);
    });
  }

  @JSExport()
  int xFullPathname(
    ExternalDartReference<VirtualFileSystem> vfs,
    Pointer zName,
    int nOut,
    Pointer zOut,
  ) {
    return _runVfs(() {
      final path = memory.readString(zName);
      final fullPath = vfs.toDartObject.xFullPathName(path);
      final encoded = utf8.encode(fullPath);

      if (encoded.length >= nOut) {
        throw VfsException(SqlError.SQLITE_CANTOPEN);
      }

      memory.asBytes
        ..setAll(zOut, encoded)
        ..[zOut + encoded.length] = 0;
    });
  }

  @JSExport()
  int xRandomness(
    ExternalDartReference<VirtualFileSystem>? vfs,
    int nByte,
    Pointer zOut,
  ) {
    return _runVfs(() {
      final target = memory.buffer.toDart.asUint8List(zOut, nByte);

      if (vfs != null) {
        vfs.toDartObject.xRandomness(target);
      } else {
        // Fall back to a default random source. We're using this to
        // implement `getentropy` in C which is used by sqlite3mc.
        return BaseVirtualFileSystem.generateRandomness(target);
      }
    });
  }

  @JSExport()
  int xSleep(ExternalDartReference<VirtualFileSystem> vfs, int micros) {
    return _runVfs(() {
      vfs.toDartObject.xSleep(Duration(microseconds: micros));
    });
  }

  @JSExport()
  int xCurrentTimeInt64(
    ExternalDartReference<VirtualFileSystem> vfs,
    Pointer target,
  ) {
    return _runVfs(() {
      final time = vfs.toDartObject.xCurrentTime();

      // dartvfs_currentTimeInt64 will turn this into the right value, it's
      // annoying to do in JS due to the lack of proper ints.
      memory.setInt64Value(
        target,
        JsBigInt.fromInt(time.millisecondsSinceEpoch),
      );
    });
  }

  @JSExport()
  int xClose(ExternalDartReference<VirtualFileSystemFile> file) {
    return _runVfs(() => file.toDartObject.xClose());
  }

  @JSExport()
  int xRead(
    ExternalDartReference<VirtualFileSystemFile> file,
    Pointer target,
    int amount,
    JSBigInt offset,
  ) {
    return _runVfs(() {
      file.toDartObject.xRead(
        memory.buffer.toDart.asUint8List(target, amount),
        JsBigInt(offset).asDartInt,
      );
    });
  }

  @JSExport()
  int xWrite(
    ExternalDartReference<VirtualFileSystemFile> file,
    Pointer source,
    int amount,
    JSBigInt offset,
  ) {
    return _runVfs(() {
      file.toDartObject.xWrite(
        memory.buffer.toDart.asUint8List(source, amount),
        JsBigInt(offset).asDartInt,
      );
    });
  }

  @JSExport()
  int xTruncate(
    ExternalDartReference<VirtualFileSystemFile> file,
    JSBigInt size,
  ) {
    return _runVfs(() => file.toDartObject.xTruncate(JsBigInt(size).asDartInt));
  }

  @JSExport()
  int xSync(ExternalDartReference<VirtualFileSystemFile> file, int flags) {
    return _runVfs(() => file.toDartObject.xSync(flags));
  }

  /// Legacy variant of [xFileSize64] writing a 32-bit int, only used by older
  /// WebAssembly modules.
  @JSExport()
  int xFileSize(
    ExternalDartReference<VirtualFileSystemFile> file,
    Pointer sizePtr,
  ) {
    return _runVfs(() {
      final size = file.toDartObject.xFileSize();
      if (size > 0x7FFFFFFF) {
        // Old modules can't represent this, so report an error instead of
        // truncating the size.
        throw VfsException(SqlExtendedError.SQLITE_IOERR_FSTAT);
      }

      memory.setInt32Value(sizePtr, size);
    });
  }

  @JSExport()
  int xFileSize64(
    ExternalDartReference<VirtualFileSystemFile> file,
    Pointer sizePtr,
  ) {
    return _runVfs(() {
      final size = file.toDartObject.xFileSize();
      memory.setInt64Value(sizePtr, JsBigInt.fromInt(size));
    });
  }

  @JSExport()
  int xLock(ExternalDartReference<VirtualFileSystemFile> file, int flags) {
    return _runVfs(() => file.toDartObject.xLock(flags));
  }

  @JSExport()
  int xUnlock(ExternalDartReference<VirtualFileSystemFile> file, int flags) {
    return _runVfs(() => file.toDartObject.xUnlock(flags));
  }

  @JSExport()
  int xCheckReservedLock(
    ExternalDartReference<VirtualFileSystemFile> file,
    Pointer pResOut,
  ) {
    return _runVfs(() {
      final status = file.toDartObject.xCheckReservedLock();
      memory.setInt32Value(pResOut, status);
    });
  }

  @JSExport()
  int xDeviceCharacteristics(
    ExternalDartReference<VirtualFileSystemFile> file,
  ) {
    return _catchAll(() => file.toDartObject.xDeviceCharacteristics, 0);
  }

  @JSExport()
  int xFileControl(
    ExternalDartReference<VirtualFileSystemFile> file,
    int op,
    int pArg,
  ) {
    return _catchAll(() {
      final asDart = file.toDartObject;
      if (asDart is VirtualFileSystemFileV1) {
        return asDart.xFileControl(SqliteFileControl(op), pArg);
      }

      return SqlError.SQLITE_NOTFOUND;
    }, SqlError.SQLITE_IOERR);
  }

  @JSExport()
  int xSectorSize(ExternalDartReference<VirtualFileSystemFile> file) {
    return _catchAll(() {
      final asDart = file.toDartObject;
      if (asDart is VirtualFileSystemFileV1) {
        return asDart.xSectorSize;
      }

      return 4096;
    }, 4096);
  }

  @JSExport('dispatch_()v')
  void dispatchVoid(ExternalDartReference<void Function()> fn) {
    _catchAll(fn.toDartObject, null);
  }

  @JSExport('dispatch_()i')
  int dispatchInt(ExternalDartReference<int Function()> fn) {
    // This is used for commit hooks, where a non-zero return value turns the
    // commit into a rollback.
    return _catchAll(fn.toDartObject, 1);
  }

  @JSExport('dispatch_update')
  void dispatchUpdateHook(
    ExternalDartReference<RawUpdateHook> fn,
    int kind,
    Pointer _,
    Pointer table,
    JSBigInt rowId,
  ) {
    _catchAll(() {
      final tableName = memory.readString(table);
      fn.toDartObject(kind, tableName, JsBigInt(rowId).asDartInt);
    }, null);
  }

  @JSExport('dispatch_xFunc')
  void dispatchXFunc(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
    int nArgs,
    Pointer value,
  ) {
    _runFunction(ctx, (context) {
      functions.toDartObject.xFunc!(
        context,
        WasmValueList(bindings, nArgs, value),
      );
    });
  }

  @JSExport('dispatch_xStep')
  void dispatchXStep(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
    int nArgs,
    Pointer value,
  ) {
    _runFunction(ctx, (context) {
      functions.toDartObject.xStep!(
        context,
        WasmValueList(bindings, nArgs, value),
      );
    });
  }

  @JSExport('dispatch_xInverse')
  void dispatchXInverse(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
    int nArgs,
    Pointer value,
  ) {
    _runFunction(ctx, (context) {
      functions.toDartObject.xInverse!(
        context,
        WasmValueList(bindings, nArgs, value),
      );
    });
  }

  @JSExport('dispatch_xValue')
  void dispatchXValue(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
  ) {
    _runFunction(ctx, functions.toDartObject.xValue!);
  }

  @JSExport('dispatch_xFinal')
  void dispatchXFinal(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
  ) {
    _runFunction(ctx, functions.toDartObject.xFinal!);
  }

  @JSExport('dispatch_compare')
  int dispatchXCompare(
    ExternalDartReference<RegisteredFunctionSet> functions,
    int lengthA,
    Pointer a,
    int lengthB,
    int b,
  ) {
    return _catchAll(() {
      final aStr = memory.readNullableString(a, lengthA);
      final bStr = memory.readNullableString(b, lengthB);

      return functions.toDartObject.collation!(aStr, bStr);
    }, 0);
  }

  @JSExport('dispatch_busy')
  int dispatchBusyHandler(
    ExternalDartReference<int Function(int)> function,
    int amount,
  ) {
    return _catchAll(() => function.toDartObject(amount), 0);
  }

  @JSExport('changeset_apply_filter')
  int dispatchApplyFilter(
    ExternalDartReference<SessionApplyCallbacks> callbacks,
    Pointer zTab,
  ) {
    return _catchAll(() => callbacks.toDartObject.filter!(zTab), 1);
  }

  @JSExport('changeset_apply_conflict')
  int dispatchApplyConflict(
    ExternalDartReference<SessionApplyCallbacks> callbacks,
    int eConflict,
    Pointer iterator,
  ) {
    return _catchAll(
      () => callbacks.toDartObject.conflict!(eConflict, iterator),
      ApplyChangesetConflict.abort.flag,
    );
  }

  void _runFunction(Pointer ctx, void Function(WasmContext) body) {
    final context = WasmContext(bindings, ctx, this);
    try {
      body(context);
    } on Object catch (e) {
      context.sqlite3_result_error(Error.safeToString(e));
    }
  }
}

/// Runs [body], returning [onError] if it throws.
T _catchAll<T>(T Function() body, T onError) {
  T result;

  try {
    result = body();
  } on Object catch (e, s) {
    Zone.current.handleUncaughtError(e, s);
    result = onError;
  }

  return result;
}

int _runVfs(void Function() body) {
  var code = SqlError.SQLITE_OK;

  try {
    body();
  } on VfsException catch (e) {
    code = e.returnCode;
  } on Object catch (e, s) {
    assert(() {
      // In debug builds, surface these errors.
      Zone.current.handleUncaughtError(e, s);
      return true;
    }());

    code = SqlError.SQLITE_ERROR;
  }

  return code;
}

final class RegisteredFunctionSet {
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
