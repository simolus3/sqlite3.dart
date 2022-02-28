// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:wasm_interop/wasm_interop.dart';

import 'big_int.dart';
import 'environment.dart';

typedef Pointer = int;

class WasmBindings {
  // We're compiling to 32bit wasm
  static const pointerSize = 4;

  final Instance instance;
  final Memory memory;

  Uint8List get memoryAsBytes => memory.buffer.asUint8List();

  Uint32List get memoryAsWords => memory.buffer.asUint32List();

  final Function _malloc,
      _free,
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
      _sqlite3_last_insert_rowid;

  final Global _sqlite3_temp_directory;

  WasmBindings(this.instance, this.memory)
      : _malloc = instance.functions['dart_sqlite3_malloc']!,
        _free = instance.functions['dart_sqlite3_free']!,
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
        _sqlite3_temp_directory = instance.globals['sqlite3_temp_directory']!;

  static Map<String, Map<String, Object>> _importMap(
      Memory memory, SqliteEnvironment environment) {
    return {
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
        'now': allowInterop((Pointer out) {
          memory.buffer
              .asByteData()
              .setUint64(out, DateTime.now().millisecondsSinceEpoch);
        }),
      }
    };
  }

  factory WasmBindings.instantiate(
      Module module, SqliteEnvironment environment) {
    final memory = Memory(initial: 16);

    final instance =
        Instance.fromModule(module, importMap: _importMap(memory, environment));

    return WasmBindings(instance, memory);
  }

  static Future<WasmBindings> instantiateAsync(
      Module module, SqliteEnvironment environment) async {
    final memory = Memory(initial: 16);

    final instance = await Instance.fromModuleAsync(module,
        importMap: _importMap(memory, environment));

    return WasmBindings(instance, memory);
  }

  Pointer allocateBytes(List<int> bytes, {int additionalLength = 0}) {
    final ptr = malloc(bytes.length + additionalLength);

    for (var i = 0; i < bytes.length; i++) {
      memoryAsBytes[ptr + i] = bytes[i];
    }
    return ptr;
  }

  Pointer allocateZeroTerminated(String string) {
    return allocateBytes(utf8.encode(string), additionalLength: 1);
  }

  Pointer malloc(int size) {
    return _malloc(size) as Pointer;
  }

  int int32ValueOfPointer(Pointer pointer) {
    return memoryAsWords[pointer >> 2];
  }

  void free(Pointer pointer) {
    _free(pointer);
  }

  void sqlite3_free(Pointer ptr) => _sqlite3_free(ptr);

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

  Pointer sqlite3_errstr(Pointer db) => _sqlite3_errstr(db) as Pointer;

  int sqlite3_extended_result_codes(Pointer db, int onoff) {
    return _sqlite3_extended_result_codes(db, onoff) as int;
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
    return _sqlite3_bind_int64(stmt, index, bigIntToJs(value)) as int;
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
    return _sqlite3_bind_blob64(stmt, index, test, length, a) as int;
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

  BigInt sqlite3_column_int64(Pointer stmt, int index) {
    return jsToBigInt(_sqlite3_column_int64(stmt, index) as Object);
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

  int sqlite3_step(Pointer stmt) => _sqlite3_step(stmt) as int;

  int sqlite3_reset(Pointer stmt) => _sqlite3_reset(stmt) as int;

  int sqlite3_finalize(Pointer stmt) => _sqlite3_finalize(stmt) as int;

  int sqlite3_changed(Pointer db) => _sqlite3_changes(db) as int;

  int sqlite3_last_insert_rowid(Pointer db) =>
      _sqlite3_last_insert_rowid(db) as int;

  Pointer get sqlite3_temp_directory {
    return (_sqlite3_temp_directory.value! as BigInt).toInt();
  }

  set sqlite3_temp_directory(Pointer value) {
    _sqlite3_temp_directory.value = value;
  }
}

extension ReadMemory on Memory {
  int strlen(int address) {
    var length = 0;
    final bytes = buffer.asUint8List();
    while (bytes[address + length] != 0) {
      length++;
    }

    return length;
  }

  String readString(int address, [int? length]) {
    return utf8.decode(buffer.asUint8List(address, length ?? strlen(address)));
  }

  Uint8List copyRange(Pointer pointer, int length) {
    final list = Uint8List(length);
    list.setAll(0, buffer.asUint8List(pointer, length));
    return list;
  }
}
