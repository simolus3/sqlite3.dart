import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

import 'fetch.dart';

@JS('WebAssembly.Instance')
class _WasmInstance {
  external Object get exports;
}

@JS()
class _ResultObject {
  external _WasmInstance get instance;
}

@JS('WebAssembly.instantiateStreaming')
external Object instantiateStreaming(Object source, Object imports);

class WasmInstance {
  final Map<String, Function> functions = {};
  final Map<String, Global> globals = {};

  WasmInstance._(_WasmInstance nativeInstance) {
    for (final key in objectKeys(nativeInstance.exports).cast<String>()) {
      final value = getProperty<Object>(nativeInstance.exports, key);

      if (value is Function) {
        functions[key] = value;
      } else if (value is Global) {
        globals[key] = value;
      }
    }
  }

  static Future<WasmInstance> load(
    Response response,
    Map<String, Map<String, Object>> imports,
  ) async {
    final importsJs = newObject<Object>();

    imports.forEach((module, moduleImports) {
      final moduleJs = newObject<Object>();
      setProperty(importsJs, module, moduleJs);

      moduleImports.forEach((name, value) {
        setProperty(moduleJs, name, value);
      });
    });

    final native = await promiseToFuture<_ResultObject>(
        instantiateStreaming(response, importsJs));
    return WasmInstance._(native.instance);
  }
}

@JS()
@anonymous
class MemoryDescriptor {
  external factory MemoryDescriptor(
      {required int initial, int? maximum, bool? shared});
}

@JS('WebAssembly.Memory')
class Memory {
  external Memory(MemoryDescriptor descriptor);

  external ByteBuffer get buffer;
}

@JS('WebAssembly.Global')
class Global {
  external int value;
}
