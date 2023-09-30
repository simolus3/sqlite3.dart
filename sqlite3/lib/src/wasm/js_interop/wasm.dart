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

@JS()
class WebAssembly {
  static Object get _instance => getProperty(globalThis, 'WebAssembly');

  @JS()
  external static Object instantiate(Uint8List bytecode, Object imports);

  @JS()
  external static Object instantiateStreaming(Object source, Object imports);

  static bool get supportsInstantiateStreaming {
    return hasProperty(_instance, 'instantiateStreaming');
  }
}

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

    final Object promise;
    if (WebAssembly.supportsInstantiateStreaming) {
      promise = WebAssembly.instantiateStreaming(response, importsJs);
    } else {
      final bytes = (await response.arrayBuffer()).asUint8List();
      promise = WebAssembly.instantiate(bytes, importsJs);
    }

    final native = await promiseToFuture<_ResultObject>(promise);
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
@staticInterop
class Memory {
  external factory Memory(MemoryDescriptor descriptor);
}

extension MemoryApi on Memory {
  @JS()
  external ByteBuffer get buffer;
}

@JS('WebAssembly.Global')
class Global {
  external int value;
}
