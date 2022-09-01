import 'dart:async';
import 'dart:html';
import 'dart:indexed_db';
import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('BigInt')
external Object _bigInt(Object s);

@JS('Number')
external int _number(Object obj);

@JS('self')
external _JsContext get self;

@JS()
@staticInterop
class _JsContext {}

// Doing KeyRange.only / KeyRange.bound in Dart will look up the factory from
// `window`, but we want to look it up from `self` to support workers.
@JS('IDBKeyRange.only')
external KeyRange keyRangeOnly(dynamic vaue);

@JS('IDBKeyRange.bound')
external KeyRange keyRangeBound(dynamic lower, dynamic higher);

extension ObjectStoreExt on ObjectStore {
  @JS("put")
  external Request _put_1(dynamic value, dynamic key);

  @JS("put")
  external Request _put_2(dynamic value);

  @JS('get')
  external Request getValue(dynamic key);

  /// Creates a request to add a value to this object store.
  ///
  /// This must only be called with native JavaScript objects, as complex Dart
  /// objects aren't serialized here.
  Request putRequestUnsafe(dynamic value, [dynamic key]) {
    if (key != null) {
      return _put_1(value, key);
    }
    return _put_2(value);
  }

  @JS('openCursor')
  external Request openCursorNative(Object? range);

  @JS('openCursor')
  external Request openCursorNative2(Object? range, String direction);
}

extension IndexExt on Index {
  @JS('openKeyCursor')
  external Request openKeyCursorNative();
}

extension RequestExt on Request {
  @JS('result')
  external dynamic get _rawResult;

  /// A [StreamIterator] to asynchronously iterate over a [Cursor].
  ///
  /// Dart provides a streaming view over cursors, but the confusing pause
  /// behavior of `await for` loops and IndexedDB's behavior of closing
  /// transactions that are not immediately used after an event leads to code
  /// that is hard to reason about.
  ///
  /// An explicit pull-based model makes it easy to iterate over values in a
  /// cursor while also being clearer about asynchronous suspensions one might
  /// want to avoid.
  StreamIterator<T> cursorIterator<T extends Cursor>() {
    return _CursorReader(this);
  }

  /// Await this request.
  ///
  /// Unlike the request-to-future API from `dart:indexeddb`, this method
  /// reports a proper error if one occurs. Further, there's the option of not
  /// deserializing IndexedDB objects. When [convertResultToDart] (which
  /// defaults to true) is set to false, the direct JS object stored in an
  /// object store will be loaded. It will not be deserialized into a Dart [Map]
  /// in that case.
  Future<T> completed<T>({bool convertResultToDart = true}) {
    final completer = Completer<T>.sync();

    StreamSubscription<void>? success, error;

    void cancel() {
      success?.cancel();
      error?.cancel();
    }

    success = onSuccess.listen((_) {
      cancel();

      // Wrapping with Future.sync in case the cast fails
      completer.complete(
          Future.sync(() => (convertResultToDart ? result : _rawResult) as T));
    });

    error = onError.listen((event) {
      cancel();
      completer.completeError(error ?? event);
    });

    return completer.future;
  }
}

class _CursorReader<T extends Cursor> implements StreamIterator<T> {
  T? _cursor;
  StreamSubscription<void>? _onSuccess, _onError;

  final Request _cursorRequest;

  _CursorReader(this._cursorRequest);

  @override
  Future<void> cancel() async {
    unawaited(_onSuccess?.cancel());
    unawaited(_onError?.cancel());

    _onSuccess = null;
    _onError = null;
  }

  @override
  T get current => _cursor ?? (throw StateError('Await moveNext() first'));

  @override
  Future<bool> moveNext() {
    assert(_onSuccess == null && _onError == null, 'moveNext() called twice');
    _cursor?.next();

    final completer = Completer<bool>.sync();
    _onSuccess = _cursorRequest.onSuccess.listen((event) {
      cancel();

      _cursor = _cursorRequest._rawResult as T?;
      completer.complete(_cursor != null);
    });

    _onError = _cursorRequest.onSuccess.listen((event) {
      cancel();
      completer.completeError(_cursorRequest.error ?? event);
    });

    return completer.future;
  }
}

extension JsContext on _JsContext {
  @JS()
  external IdbFactory? get indexedDB;
}

extension IdbFactoryExt on IdbFactory {
  @JS('databases')
  external Object _jsDatabases();

  Future<List<DatabaseName>?> databases() async {
    if (!hasProperty(this, 'databases')) {
      return null;
    }
    final jsDatabases = await promiseToFuture<List<dynamic>>(_jsDatabases());
    return jsDatabases.cast<DatabaseName>();
  }
}

@JS()
@anonymous
class DatabaseName {
  external String get name;
  external int get version;
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

    return lessThanOrEqual<Object>(minSafeInteger, _jsBigInt) &&
        lessThanOrEqual<Object>(_jsBigInt, maxSafeInteger);
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
  external factory Response(
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
