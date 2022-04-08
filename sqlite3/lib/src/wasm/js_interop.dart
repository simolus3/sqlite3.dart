@internal
import 'dart:html';
import 'dart:indexed_db';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:meta/meta.dart';

@JS('BigInt')
external Object _bigInt(Object s);

@JS('Number')
external int _number(Object obj);

@JS('eval')
external Object _eval(String s);

@JS('Object.keys')
external List<Object> _objectKeys(Object value);

@JS('self')
external _JsContext get self;

bool Function(Object, Object) _leq =
    _eval('(a,b)=>a<=b') as bool Function(Object, Object);

@JS()
@staticInterop
class _JsContext {}

extension JsContext on _JsContext {
  @JS()
  external IdbFactory? get indexedDB;
}

class JsBigInt {
  /// The BigInt literal as a raw JS value.
  final Object _jsBigInt;

  JsBigInt(this._jsBigInt);

  factory JsBigInt.parse(String s) => JsBigInt(_bigInt(s));
  factory JsBigInt.fromInt(int i) => JsBigInt(_bigInt(i));
  factory JsBigInt.fromBigInt(BigInt i) => JsBigInt.parse(i.toString());

  int get asDartInt => _number(_jsBigInt);

  BigInt get asDartBigInt => BigInt.parse(toString());

  Object get jsObject => _jsBigInt;

  bool get isSafeInteger {
    const maxSafeInteger = 9007199254740992;
    const minSafeInteger = -maxSafeInteger;

    return _leq(minSafeInteger, _jsBigInt) && _leq(_jsBigInt, maxSafeInteger);
  }

  Object toDart() {
    return isSafeInteger ? asDartInt : asDartBigInt;
  }

  @override
  String toString() {
    return callMethod(_jsBigInt, 'toString', const []);
  }
}

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

  WasmInstance(_WasmInstance nativeInstance) {
    for (final key in _objectKeys(nativeInstance.exports).cast<String>()) {
      final value = getProperty<Object>(nativeInstance.exports, key);

      if (value is Function) {
        functions[key] = value;
      } else if (value is Global) {
        globals[key] = value;
      }
    }
  }

  static Future<WasmInstance> load(
    Uint8List source,
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

    final headers = newObject<Object>();
    setProperty(headers, 'content-type', 'application/wasm');

    final native = await promiseToFuture<_ResultObject>(instantiateStreaming(
        Response(source, ResponseInit(headers: headers)), importsJs));
    return WasmInstance(native.instance);
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

@JS()
@anonymous
class ResponseInit {
  external factory ResponseInit(
      {int? status, String? statusText, Object? headers});
}

@JS()
@staticInterop
class Response {
  external Response(
      Object /* Blob|BufferSource|FormData|ReadableStream|URLSearchParams|UVString */ body,
      ResponseInit init);
}

extension ReadBlob on Blob {
  Future<Uint8List> arrayBuffer() async {
    final buffer = await promiseToFuture<ByteBuffer>(
        callMethod(this, 'arrayBuffer', const []));
    return buffer.asUint8List();
  }
}
