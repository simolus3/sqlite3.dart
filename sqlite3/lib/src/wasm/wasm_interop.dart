// ignore_for_file: avoid_dynamic_calls
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:path/path.dart' as p;

import '../../wasm.dart';
import '../implementation/bindings.dart';
import 'bindings.dart';
import 'js_interop.dart';

// ignore_for_file: non_constant_identifier_names

typedef Pointer = int;

final _context = p.Context(style: p.Style.url, current: '/');

class WasmBindings {
  // We're compiling to 32bit wasm
  static const pointerSize = 4;

  final WasmInstance instance;
  final Memory memory;

  final DartCallbacks callbacks;

  Uint8List get memoryAsBytes => memory.buffer.asUint8List();

  Uint32List get memoryAsWords => memory.buffer.asUint32List();

  final Function _malloc,
      _free,
      _create_scalar,
      _create_aggregate,
      _update_hooks,
      _sqlite3_libversion,
      _sqlite3_sourceid,
      _sqlite3_libversion_number,
      _sqlite3_open_v2,
      _sqlite3_close_v2,
      _sqlite3_extended_errcode,
      _sqlite3_errmsg,
      _sqlite3_errstr,
      _sqlite3_extended_result_codes,
      _sqlite3_exec,
      _sqlite3_free,
      _sqlite3_prepare_v3,
      _sqlite3_bind_parameter_count,
      _sqlite3_column_count,
      _sqlite3_column_name,
      _sqlite3_reset,
      _sqlite3_step,
      _sqlite3_column_type,
      _sqlite3_column_int64,
      _sqlite3_column_double,
      _sqlite3_column_bytes,
      _sqlite3_column_text,
      _sqlite3_column_blob,
      _sqlite3_bind_null,
      _sqlite3_bind_int64,
      _sqlite3_bind_double,
      _sqlite3_bind_text,
      _sqlite3_bind_blob64,
      _sqlite3_bind_parameter_index,
      _sqlite3_finalize,
      _sqlite3_changes,
      _sqlite3_last_insert_rowid,
      _sqlite3_user_data,
      _sqlite3_result_null,
      _sqlite3_result_int64,
      _sqlite3_result_double,
      _sqlite3_result_text,
      _sqlite3_result_blob64,
      _sqlite3_result_error,
      _sqlite3_value_type,
      _sqlite3_value_int64,
      _sqlite3_value_double,
      _sqlite3_value_bytes,
      _sqlite3_value_text,
      _sqlite3_value_blob,
      _sqlite3_aggregate_context;

  // These functions were added in more recent versions of our compiled sqlite3
  // wasm bundle. For backwards compatibility, we only access these functions
  // when needed.
  final Function? _create_window, _create_collation;

  final Global _sqlite3_temp_directory;

  WasmBindings._(this.instance, _InjectedValues values)
      : memory = values.memory,
        callbacks = values.callbacks,
        _malloc = instance.functions['dart_sqlite3_malloc']!,
        _free = instance.functions['dart_sqlite3_free']!,
        _create_scalar =
            instance.functions['dart_sqlite3_create_scalar_function']!,
        _create_aggregate =
            instance.functions['dart_sqlite3_create_aggregate_function']!,
        _create_window =
            instance.functions['dart_sqlite3_create_window_function'],
        _create_collation = instance.functions['dart_sqlite3_create_collation'],
        _update_hooks = instance.functions['dart_sqlite3_updates']!,
        _sqlite3_libversion = instance.functions['sqlite3_libversion']!,
        _sqlite3_sourceid = instance.functions['sqlite3_sourceid']!,
        _sqlite3_libversion_number =
            instance.functions['sqlite3_libversion_number']!,
        _sqlite3_open_v2 = instance.functions['sqlite3_open_v2']!,
        _sqlite3_close_v2 = instance.functions['sqlite3_close_v2']!,
        _sqlite3_extended_errcode =
            instance.functions['sqlite3_extended_errcode']!,
        _sqlite3_errmsg = instance.functions['sqlite3_errmsg']!,
        _sqlite3_errstr = instance.functions['sqlite3_errstr']!,
        _sqlite3_extended_result_codes =
            instance.functions['sqlite3_extended_result_codes']!,
        _sqlite3_exec = instance.functions['sqlite3_exec']!,
        _sqlite3_free = instance.functions['sqlite3_free']!,
        _sqlite3_prepare_v3 = instance.functions['sqlite3_prepare_v3']!,
        _sqlite3_bind_parameter_count =
            instance.functions['sqlite3_bind_parameter_count']!,
        _sqlite3_column_count = instance.functions['sqlite3_column_count']!,
        _sqlite3_column_name = instance.functions['sqlite3_column_name']!,
        _sqlite3_reset = instance.functions['sqlite3_reset']!,
        _sqlite3_step = instance.functions['sqlite3_step']!,
        _sqlite3_finalize = instance.functions['sqlite3_finalize']!,
        _sqlite3_column_type = instance.functions['sqlite3_column_type']!,
        _sqlite3_column_int64 = instance.functions['sqlite3_column_int64']!,
        _sqlite3_column_double = instance.functions['sqlite3_column_double']!,
        _sqlite3_column_bytes = instance.functions['sqlite3_column_bytes']!,
        _sqlite3_column_blob = instance.functions['sqlite3_column_blob']!,
        _sqlite3_column_text = instance.functions['sqlite3_column_text']!,
        _sqlite3_bind_null = instance.functions['sqlite3_bind_null']!,
        _sqlite3_bind_int64 = instance.functions['sqlite3_bind_int64']!,
        _sqlite3_bind_double = instance.functions['sqlite3_bind_double']!,
        _sqlite3_bind_text = instance.functions['sqlite3_bind_text']!,
        _sqlite3_bind_blob64 = instance.functions['sqlite3_bind_blob64']!,
        _sqlite3_bind_parameter_index =
            instance.functions['sqlite3_bind_parameter_index']!,
        _sqlite3_changes = instance.functions['sqlite3_changes']!,
        _sqlite3_last_insert_rowid =
            instance.functions['sqlite3_last_insert_rowid']!,
        _sqlite3_user_data = instance.functions['sqlite3_user_data']!,
        _sqlite3_result_null = instance.functions['sqlite3_result_null']!,
        _sqlite3_result_int64 = instance.functions['sqlite3_result_int64']!,
        _sqlite3_result_double = instance.functions['sqlite3_result_double']!,
        _sqlite3_result_text = instance.functions['sqlite3_result_text']!,
        _sqlite3_result_blob64 = instance.functions['sqlite3_result_blob64']!,
        _sqlite3_result_error = instance.functions['sqlite3_result_error']!,
        _sqlite3_value_type = instance.functions['sqlite3_value_type']!,
        _sqlite3_value_int64 = instance.functions['sqlite3_value_int64']!,
        _sqlite3_value_double = instance.functions['sqlite3_value_double']!,
        _sqlite3_value_bytes = instance.functions['sqlite3_value_bytes']!,
        _sqlite3_value_text = instance.functions['sqlite3_value_text']!,
        _sqlite3_value_blob = instance.functions['sqlite3_value_blob']!,
        _sqlite3_aggregate_context =
            instance.functions['sqlite3_aggregate_context']!,
        _sqlite3_temp_directory = instance.globals['sqlite3_temp_directory']! {
    values.bindings = this;
  }

  static Future<WasmBindings> instantiateAsync(
      Response response, SqliteEnvironment environment) async {
    final injected = _InjectedValues(environment);
    final instance = await WasmInstance.load(response, injected.injectedValues);

    return WasmBindings._(instance, injected);
  }

  Function _checkForPresence(Function? function, String name) {
    if (function == null) {
      throw UnsupportedError(
          '$name is not supported by WASM sqlite3, try upgrading to '
          'a more recent sqlite3.wasm');
    }

    return function;
  }

  Pointer allocateBytes(List<int> bytes, {int additionalLength = 0}) {
    final ptr = malloc(bytes.length + additionalLength);
    memoryAsBytes
      ..setRange(ptr, ptr + bytes.length, bytes)
      ..fillRange(ptr + bytes.length, ptr + bytes.length + additionalLength, 0);

    return ptr;
  }

  Pointer allocateZeroTerminated(String string) {
    return allocateBytes(utf8.encode(string), additionalLength: 1);
  }

  Pointer malloc(int size) {
    return _malloc(size) as Pointer;
  }

  int int32ValueOfPointer(Pointer pointer) {
    assert(pointer != 0, 'Null pointer dereference');
    return memoryAsWords[pointer >> 2];
  }

  void setInt32Value(Pointer pointer, int value) {
    assert(pointer != 0, 'Null pointer dereference');
    memoryAsWords[pointer >> 2] = value;
  }

  void free(Pointer pointer) {
    _free(pointer);
  }

  void sqlite3_free(Pointer ptr) => _sqlite3_free(ptr);

  int create_scalar_function(
      Pointer db, Pointer functionName, int nArg, int eTextRep, int id) {
    return _create_scalar(db, functionName, nArg, eTextRep, id) as int;
  }

  int create_aggregate_function(
      Pointer db, Pointer functionName, int nArg, int eTextRep, int id) {
    return _create_aggregate(db, functionName, nArg, eTextRep, id) as int;
  }

  int create_window_function(
      Pointer db, Pointer functionName, int nArg, int eTextRep, int id) {
    final function = _checkForPresence(_create_window, 'createWindow');
    return function(db, functionName, nArg, eTextRep, id) as int;
  }

  int create_collation(Pointer db, Pointer name, int eTextRep, int id) {
    final function = _checkForPresence(_create_collation, 'createCollation');
    return function(db, name, eTextRep, id) as int;
  }

  int sqlite3_libversion() => _sqlite3_libversion() as int;

  Pointer sqlite3_sourceid() => _sqlite3_sourceid() as Pointer;

  int sqlite3_libversion_number() => _sqlite3_libversion_number() as int;

  int sqlite3_open_v2(Pointer filename, Pointer ppDb, int flags, Pointer zVfs) {
    return _sqlite3_open_v2(filename, ppDb, flags, zVfs) as int;
  }

  int sqlite3_close_v2(Pointer db) => _sqlite3_close_v2(db) as int;

  int sqlite3_extended_errcode(Pointer db) =>
      _sqlite3_extended_errcode(db) as int;

  Pointer sqlite3_errmsg(Pointer db) => _sqlite3_errmsg(db) as Pointer;

  Pointer sqlite3_errstr(int resultCode) =>
      _sqlite3_errstr(resultCode) as Pointer;

  int sqlite3_extended_result_codes(Pointer db, int onoff) {
    return _sqlite3_extended_result_codes(db, onoff) as int;
  }

  /// Pass a non-negative [id] to enable update tracking on the db, a negative
  /// one to stop it.
  void dart_sqlite3_updates(Pointer db, int id) {
    _update_hooks(db, id);
  }

  int sqlite3_exec(Pointer db, Pointer sql, Pointer callback,
      Pointer callbackArg, Pointer errorOut) {
    return _sqlite3_exec(db, sql, callback, callbackArg, errorOut) as int;
  }

  int sqlite3_prepare_v3(Pointer db, Pointer sql, int length, int prepFlags,
      Pointer ppStmt, Pointer pzTail) {
    return _sqlite3_prepare_v3(db, sql, length, prepFlags, ppStmt, pzTail)
        as int;
  }

  int sqlite3_bind_parameter_count(Pointer stmt) {
    return _sqlite3_bind_parameter_count(stmt) as int;
  }

  int sqlite3_bind_null(Pointer stmt, int index) {
    return _sqlite3_bind_null(stmt, index) as int;
  }

  int sqlite3_bind_int64(Pointer stmt, int index, BigInt value) {
    return _sqlite3_bind_int64(stmt, index, JsBigInt.fromBigInt(value).jsObject)
        as int;
  }

  int sqlite3_bind_int(Pointer stmt, int index, int value) {
    return _sqlite3_bind_int64(stmt, index, JsBigInt.fromInt(value).jsObject)
        as int;
  }

  int sqlite3_bind_double(Pointer stmt, int index, double value) {
    return _sqlite3_bind_double(stmt, index, value) as int;
  }

  int sqlite3_bind_text(
      Pointer stmt, int index, Pointer text, int length, Pointer a) {
    return _sqlite3_bind_text(stmt, index, text, length, a) as int;
  }

  int sqlite3_bind_blob64(
      Pointer stmt, int index, Pointer test, int length, Pointer a) {
    return _sqlite3_bind_blob64(
        stmt, index, test, JsBigInt.fromInt(length).jsObject, a) as int;
  }

  int sqlite3_bind_parameter_index(Pointer statement, Pointer key) {
    return _sqlite3_bind_parameter_index(statement, key) as int;
  }

  int sqlite3_column_count(Pointer stmt) {
    return _sqlite3_column_count(stmt) as int;
  }

  Pointer sqlite3_column_name(Pointer stmt, int index) {
    return _sqlite3_column_name(stmt, index) as Pointer;
  }

  int sqlite3_column_type(Pointer stmt, int index) {
    return _sqlite3_column_type(stmt, index) as Pointer;
  }

  JsBigInt sqlite3_column_int64(Pointer stmt, int index) {
    return JsBigInt(_sqlite3_column_int64(stmt, index) as Object);
  }

  double sqlite3_column_double(Pointer stmt, int index) {
    return _sqlite3_column_double(stmt, index) as double;
  }

  int sqlite3_column_bytes(Pointer stmt, int index) {
    return _sqlite3_column_bytes(stmt, index) as int;
  }

  Pointer sqlite3_column_text(Pointer stmt, int index) {
    return _sqlite3_column_text(stmt, index) as Pointer;
  }

  Pointer sqlite3_column_blob(Pointer stmt, int index) {
    return _sqlite3_column_blob(stmt, index) as Pointer;
  }

  int sqlite3_value_type(Pointer value) {
    return _sqlite3_value_type(value) as int;
  }

  JsBigInt sqlite3_value_int64(Pointer value) {
    return JsBigInt(_sqlite3_value_int64(value) as Object);
  }

  double sqlite3_value_double(Pointer value) {
    return _sqlite3_value_double(value) as double;
  }

  int sqlite3_value_bytes(Pointer value) {
    return _sqlite3_value_bytes(value) as int;
  }

  Pointer sqlite3_value_text(Pointer value) {
    return _sqlite3_value_text(value) as Pointer;
  }

  Pointer sqlite3_value_blob(Pointer value) {
    return _sqlite3_value_blob(value) as Pointer;
  }

  void sqlite3_result_null(Pointer context) {
    _sqlite3_result_null(context);
  }

  void sqlite3_result_int64(Pointer context, BigInt value) {
    _sqlite3_result_int64(context, JsBigInt.fromBigInt(value).jsObject);
  }

  void sqlite3_result_double(Pointer context, double value) {
    _sqlite3_result_double(context, value);
  }

  void sqlite3_result_text(
      Pointer context, Pointer text, int length, Pointer a) {
    _sqlite3_result_text(context, text, length, a);
  }

  void sqlite3_result_blob64(
      Pointer context, Pointer blob, int length, Pointer a) {
    _sqlite3_result_blob64(context, blob, JsBigInt.fromInt(length).jsObject, a);
  }

  void sqlite3_result_error(Pointer context, Pointer text, int length) {
    _sqlite3_result_error(context, text, length);
  }

  int sqlite3_user_data(Pointer context) {
    return _sqlite3_user_data(context) as Pointer;
  }

  Pointer sqlite3_aggregate_context(Pointer context, int nBytes) {
    return _sqlite3_aggregate_context(context, nBytes) as Pointer;
  }

  int sqlite3_step(Pointer stmt) => _sqlite3_step(stmt) as int;

  int sqlite3_reset(Pointer stmt) => _sqlite3_reset(stmt) as int;

  int sqlite3_finalize(Pointer stmt) => _sqlite3_finalize(stmt) as int;

  int sqlite3_changes(Pointer db) => _sqlite3_changes(db) as int;

  int sqlite3_last_insert_rowid(Pointer db) =>
      JsBigInt(_sqlite3_last_insert_rowid(db) as Object).asDartInt;

  Pointer get sqlite3_temp_directory {
    return _sqlite3_temp_directory.value;
  }

  set sqlite3_temp_directory(Pointer value) {
    _sqlite3_temp_directory.value = value;
  }
}

extension ReadMemory on Memory {
  int strlen(int address) {
    assert(address != 0, 'Null pointer dereference');
    var length = 0;
    final bytes = buffer.asUint8List();
    while (bytes[address + length] != 0) {
      length++;
    }

    return length;
  }

  String readString(int address, [int? length]) {
    assert(address != 0, 'Null pointer dereference');
    return utf8.decode(buffer.asUint8List(address, length ?? strlen(address)));
  }

  String? readNullableString(int address, [int? length]) {
    if (address == 0) return null;

    return utf8.decode(buffer.asUint8List(address, length ?? strlen(address)));
  }

  Uint8List copyRange(Pointer pointer, int length) {
    final list = Uint8List(length);
    list.setAll(0, buffer.asUint8List(pointer, length));
    return list;
  }
}

class _InjectedValues {
  late WasmBindings bindings;
  late Map<String, Map<String, Object>> injectedValues;

  late Memory memory;

  final DartCallbacks callbacks = DartCallbacks();

  _InjectedValues(SqliteEnvironment environment) {
    final memory = this.memory = Memory(MemoryDescriptor(initial: 16));

    injectedValues = {
      'env': {
        'memory': memory,
      },
      'dart': {
        // See assets/wasm/bridge.h
        'random': allowInterop((Pointer ptr, int length) {
          final buffer = memory.buffer.asUint8List(ptr, length);
          final random = environment.random;

          for (var i = 0; i < buffer.length; i++) {
            buffer[i] = random.nextInt(1 << 8);
          }
        }),
        'error_log': allowInterop((Pointer ptr) {
          print('Error reported by native handler: ${memory.readString(ptr)}');
        }),
        'now': allowInterop(() {
          return JsBigInt.fromInt(DateTime.now().millisecondsSinceEpoch);
        }),
        'path_normalize':
            allowInterop((Pointer source, Pointer dest, int length) {
          final normalized = _context.absolute(memory.readString(source));
          final encoded = utf8.encode(normalized);

          if (encoded.length >= length) {
            return 1;
          } else {
            memory.buffer.asUint8List(dest, length).setAll(0, encoded);
            return 0;
          }
        }),
        'function_xFunc': allowInterop((Pointer ctx, int args, Pointer value) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks.functions[id]!.xFunc!(
            WasmContext(bindings, ctx, callbacks),
            WasmValueList(bindings, args, value),
          );
        }),
        'function_xStep': allowInterop((Pointer ctx, int args, Pointer value) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks.functions[id]!.xStep!(
            WasmContext(bindings, ctx, callbacks),
            WasmValueList(bindings, args, value),
          );
        }),
        'function_xInverse':
            allowInterop((Pointer ctx, int args, Pointer value) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks.functions[id]!.xInverse!(
            WasmContext(bindings, ctx, callbacks),
            WasmValueList(bindings, args, value),
          );
        }),
        'function_xFinal': allowInterop((Pointer ctx) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks
              .functions[id]!.xFinal!(WasmContext(bindings, ctx, callbacks));
        }),
        'function_xValue': allowInterop((Pointer ctx) {
          final id = bindings.sqlite3_user_data(ctx);
          callbacks
              .functions[id]!.xValue!(WasmContext(bindings, ctx, callbacks));
        }),
        'function_forget': allowInterop((Pointer ctx) {
          callbacks.forget(ctx);
        }),
        'function_compare': allowInterop(
            (Pointer ctx, int lengthA, Pointer a, int lengthB, int b) {
          final aStr = memory.readNullableString(a, lengthA);
          final bStr = memory.readNullableString(b, lengthB);

          return callbacks.functions[ctx]!.collation!(aStr, bStr);
        }),
        'function_hook': allowInterop(
            (int id, int kind, Pointer _, Pointer table, Object rowId) {
          final tableName = memory.readString(table);

          callbacks.installedUpdateHook
              ?.call(kind, tableName, JsBigInt(rowId).asDartInt);
        }),
        'fs_create': allowInterop((Pointer path, int flags) {
          final pathStr = memory.readString(path);

          final createIfNotExists = (flags & SqlFlag.SQLITE_OPEN_CREATE) != 0;
          final exclusive = (flags & SqlFlag.SQLITE_OPEN_EXCLUSIVE) != 0;

          try {
            environment.fileSystem.createFile(
              pathStr,
              errorIfNotExists: !createIfNotExists,
              errorIfAlreadyExists: exclusive,
            );
            return 0;
          } on FileSystemException catch (e) {
            return e.errorCode;
          }
        }),
        'fs_temp_create': allowInterop(() {
          final path = environment.fileSystem.createTemporaryFile();
          return bindings.allocateZeroTerminated(path);
        }),
        'fs_size': allowInterop((Pointer path, Pointer pSize) {
          try {
            final size =
                environment.fileSystem.sizeOfFile(memory.readString(path));

            bindings
              ..setInt32Value(pSize, 0)
              ..setInt32Value(pSize + 1, size);
            return 0;
          } on FileSystemException catch (e) {
            return e.errorCode;
          }
        }),
        'fs_truncate': allowInterop((Pointer path, int size) {
          try {
            environment.fileSystem.truncateFile(memory.readString(path), size);
            return 0;
          } on FileSystemException catch (e) {
            return e.errorCode;
          }
        }),
        'fs_read': allowInterop(
            (Pointer path, Pointer into, int amount, Object offset) {
          try {
            return environment.fileSystem.read(
                memory.readString(path),
                memory.buffer.asUint8List(into, amount),
                JsBigInt(offset).asDartInt);
          } on FileSystemException catch (e) {
            return -e.errorCode;
          }
        }),
        'fs_write': allowInterop(
            (Pointer path, Pointer from, int amount, Object offset) {
          try {
            environment.fileSystem.write(
                memory.readString(path),
                memory.buffer.asUint8List(from, amount),
                JsBigInt(offset).asDartInt);
            return 0;
          } on FileSystemException catch (e) {
            return e.errorCode;
          }
        }),
        'fs_delete': allowInterop((Pointer path) {
          try {
            environment.fileSystem.deleteFile(memory.readString(path));
            return 0;
          } on FileSystemException catch (e) {
            return e.errorCode;
          }
        }),
        'fs_access': allowInterop((Pointer path, int flags, Pointer pResOut) {
          try {
            final exists =
                environment.fileSystem.exists(memory.readString(path));
            bindings.setInt32Value(pResOut, exists ? 1 : 0);
            return 0;
          } on FileSystemException catch (e) {
            return e.errorCode;
          }
        }),
      }
    };
  }
}

class DartCallbacks {
  int _id = 0;
  final Map<int, RegisteredFunctionSet> functions = {};

  int aggregateContextId = 1;
  final Map<int, AggregateContext<Object?>> aggregateContexts = {};

  RawUpdateHook? installedUpdateHook;

  int register(RegisteredFunctionSet set) {
    final id = _id++;
    functions[id] = set;
    return id;
  }

  void forget(int id) => functions.remove(id);
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
