// Dart functions that are injected into the SQLite WebAssembly module. For
// details, see sqlite3_wasm_build/bridge.h

import 'dart:convert';
import 'dart:js_interop';

import '../constants.dart';
import '../functions.dart';
import '../implementation/bindings.dart';
import '../vfs.dart';
import 'bindings.dart';
import 'js_interop.dart';
import 'sqlite3_wasm.g.dart';
import 'wasm_interop.dart';

final class DartBridgeCallbacks {
  // We only have access to these bindings after instantiating the module.
  late final WasmBindings bindings;
  final Memory memory;

  int aggregateContextId = 1;
  final Map<int, AggregateContext<Object?>> aggregateContexts = {};

  DartBridgeCallbacks(this.memory);

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
    final path = Sqlite3Filename(memory.readNullableString(zName));

    try {
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
    final path = memory.readString(zName);
    return _runVfs(() => vfs.toDartObject.xDelete(path, syncDir));
  }

  @JSExport()
  int xAccess(
    ExternalDartReference<VirtualFileSystem> vfs,
    Pointer zName,
    int flags,
    Pointer pResOut,
  ) {
    final path = memory.readString(zName);

    return _runVfs(() {
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
    final path = memory.readString(zName);

    return _runVfs(() {
      final fullPath = vfs.toDartObject.xFullPathName(path);
      final encoded = utf8.encode(fullPath);

      if (encoded.length > nOut) {
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
    final time = vfs.toDartObject.xCurrentTime();

    // dartvfs_currentTimeInt64 will turn this into the right value, it's
    // annoying to do in JS due to the lack of proper ints.
    memory.setInt64Value(target, JsBigInt.fromInt(time.millisecondsSinceEpoch));
    return 0;
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

  @JSExport()
  int xFileSize(
    ExternalDartReference<VirtualFileSystemFile> file,
    Pointer sizePtr,
  ) {
    return _runVfs(() {
      final size = file.toDartObject.xFileSize();
      memory.setInt32Value(sizePtr, size);
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
    int fd,
  ) {
    return file.toDartObject.xDeviceCharacteristics;
  }

  @JSExport('dispatch_()v')
  void dispatchVoid(ExternalDartReference<void Function()> fn) {
    fn.toDartObject();
  }

  @JSExport('dispatch_()i')
  int dispatchInt(ExternalDartReference<int Function()> fn) {
    return fn.toDartObject();
  }

  @JSExport('dispatch_update')
  void dispatchUpdateHook(
    ExternalDartReference<RawUpdateHook> fn,
    int kind,
    Pointer _,
    Pointer table,
    JSBigInt rowId,
  ) {
    final tableName = memory.readString(table);
    fn.toDartObject(kind, tableName, JsBigInt(rowId).asDartInt);
  }

  @JSExport('dispatch_xFunc')
  void dispatchXFunc(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
    int nArgs,
    Pointer value,
  ) {
    functions.toDartObject.xFunc!(
      WasmContext(bindings, ctx, this),
      WasmValueList(bindings, nArgs, value),
    );
  }

  @JSExport('dispatch_xStep')
  void dispatchXStep(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
    int nArgs,
    Pointer value,
  ) {
    functions.toDartObject.xStep!(
      WasmContext(bindings, ctx, this),
      WasmValueList(bindings, nArgs, value),
    );
  }

  @JSExport('dispatch_xInverse')
  void dispatchXInverse(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
    int nArgs,
    Pointer value,
  ) {
    functions.toDartObject.xInverse!(
      WasmContext(bindings, ctx, this),
      WasmValueList(bindings, nArgs, value),
    );
  }

  @JSExport('dispatch_xValue')
  void dispatchXValue(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
  ) {
    functions.toDartObject.xValue!(WasmContext(bindings, ctx, this));
  }

  @JSExport('dispatch_xFinal')
  void dispatchXFinal(
    ExternalDartReference<RegisteredFunctionSet> functions,
    Pointer ctx,
  ) {
    functions.toDartObject.xFinal!(WasmContext(bindings, ctx, this));
  }

  @JSExport('dispatch_compare')
  int dispatchXCompare(
    ExternalDartReference<RegisteredFunctionSet> functions,
    int lengthA,
    Pointer a,
    int lengthB,
    int b,
  ) {
    final aStr = memory.readNullableString(a, lengthA);
    final bStr = memory.readNullableString(b, lengthB);

    return functions.toDartObject.collation!(aStr, bStr);
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

final class SessionApplyCallbacks {
  final RawFilter? filter;
  final RawConflict? conflict;

  SessionApplyCallbacks(this.filter, this.conflict);
}
