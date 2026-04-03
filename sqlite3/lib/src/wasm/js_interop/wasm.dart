@JS()
library;

import 'dart:js_interop';

@JS('WebAssembly.Instance')
extension type WasmInstance._(JSObject _) implements JSObject {
  external JSObject get exports;
}

extension type ResultObject._(JSObject _) implements JSObject {
  external WasmInstance get instance;
}

@JS('WebAssembly.instantiateStreaming')
external JSPromise<ResultObject> instantiateStreaming(
  JSAny? source,
  JSObject imports,
);

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
