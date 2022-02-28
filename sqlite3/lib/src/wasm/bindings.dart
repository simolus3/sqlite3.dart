// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'dart:typed_data';

import 'package:wasm_interop/wasm_interop.dart';

typedef Pointer = int;

class WasmBindings {
  final Instance instance;
  final Memory memory;

  Uint8List get memoryAsUints => memory.buffer.asUint8List();

  final Function _malloc,
      _free,
      _sqlite3_libversion,
      _sqlite3_sourceid,
      _sqlite3_libversion_number;

  final Global _sqlite3_temp_directory;

  WasmBindings(this.instance, this.memory)
      : _malloc = instance.functions['dart_sqlite3_malloc']!,
        _free = instance.functions['dart_sqlite3_free']!,
        _sqlite3_libversion = instance.functions['sqlite3_libversion']!,
        _sqlite3_sourceid = instance.functions['sqlite3_sourceid']!,
        _sqlite3_libversion_number =
            instance.functions['sqlite3_libversion_number']!,
        _sqlite3_temp_directory = instance.globals['sqlite3_temp_directory']!;

  factory WasmBindings.instantiate(Module module) {
    final memory = Memory(initial: 16);
    final instance = Instance.fromModule(module, importMap: {
      'env': {
        'memory': memory,
      }
    });

    return WasmBindings(instance, memory);
  }

  static Future<WasmBindings> instantiateAsync(Module module) async {
    final memory = Memory(initial: 16);
    final instance = await Instance.fromModuleAsync(module, importMap: {
      'env': {
        'memory': memory,
      }
    });

    return WasmBindings(instance, memory);
  }

  int strlen(int address) {
    var length = 0;
    while (memoryAsUints[address + length] != 0) {
      length++;
    }

    return length;
  }

  String readString(int address, [int? length]) {
    return utf8
        .decode(memory.buffer.asUint8List(address, length ?? strlen(address)));
  }

  Pointer allocateBytes(List<int> bytes, {int additionalLength = 0}) {
    final ptr = malloc(bytes.length + additionalLength);

    for (var i = 0; i < bytes.length; i++) {
      memoryAsUints[ptr + i] = bytes[i];
    }
    return ptr;
  }

  Pointer allocateZeroTerminated(String string) {
    return allocateBytes(utf8.encode(string), additionalLength: 1);
  }

  Pointer malloc(int size) {
    return _malloc(size) as Pointer;
  }

  void free(Pointer pointer) {
    _free(pointer);
  }

  int sqlite3_libversion() => _sqlite3_libversion() as int;

  Pointer sqlite3_sourceid() => _sqlite3_sourceid() as Pointer;

  int sqlite3_libversion_number() => _sqlite3_libversion_number() as int;

  Pointer get sqlite3_temp_directory {
    return (_sqlite3_temp_directory.value! as BigInt).toInt();
  }

  set sqlite3_temp_directory(Pointer value) {
    _sqlite3_temp_directory.value = value;
  }
}
