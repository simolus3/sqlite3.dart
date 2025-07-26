@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('WebAssembly.Instance')
extension type WasmInstance._(JSObject _) implements JSObject {
  external JSObject get exports;

  static Future<WasmInstance> load(
    web.Response response,
    Map<String, Map<String, JSAny?>> imports,
  ) async {
    final importsJs = JSObject();

    imports.forEach((module, moduleImports) {
      final moduleJs = JSObject();
      importsJs[module] = moduleJs;

      moduleImports.forEach((name, value) {
        moduleJs[name] = value;
      });
    });

    final native = await _instantiateStreaming(response, importsJs).toDart;

    // If the module has an `_initialize` export, it needs to be called to run
    // C constructors and set up memory.
    final exports = native.instance.exports;
    if (exports.has('_initialize')) {
      (exports['_initialize'] as JSFunction).callAsFunction();
    }

    return WasmInstance._(native.instance);
  }
}

extension type _ResultObject._(JSObject _) implements JSObject {
  external WasmInstance get instance;
}

@JS('WebAssembly.instantiateStreaming')
external JSPromise<_ResultObject> _instantiateStreaming(
    JSAny? source, JSObject imports);

@JS()
extension type MemoryDescriptor._(JSObject _) implements JSObject {
  external factory MemoryDescriptor({
    required JSNumber initial,
    JSNumber? maximum,
    JSBoolean? shared,
  });
}

@JS('WebAssembly.Memory')
extension type Memory._(JSObject _) implements JSObject {
  external factory Memory(MemoryDescriptor descriptor);

  external JSArrayBuffer get buffer;
}

@JS('WebAssembly.Global')
extension type Global._(JSObject _) implements JSObject {
  external JSNumber value;
}
