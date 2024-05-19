import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'typed_data.dart';

@JS('Int32Array')
external JSFunction _int32Array;

@JS('Uint8Array')
external JSFunction _uint8Array;

@JS('DataView')
external JSFunction _dataView;

@JS()
extension type SharedArrayBuffer._(JSObject _) implements JSObject {
  external factory SharedArrayBuffer(int length);

  external int get byteLength;

  SafeI32Array asInt32List() {
    return SafeI32Array(_int32Array.callAsConstructor<JSInt32Array>(this));
  }

  SafeDataView asByteData(int offset, int length) {
    return SafeDataView(_dataView.callAsConstructor<JSDataView>(
        this, offset.toJS, length.toJS));
  }

  SafeU8Array asUint8List() {
    return SafeU8Array(_uint8Array.callAsConstructor<JSUint8Array>(this));
  }

  SafeU8Array asUint8ListSlice(int offset, int length) {
    return SafeU8Array(_uint8Array.callAsConstructor<JSUint8Array>(
        this, offset.toJS, length.toJS));
  }
}

@JS('Atomics')
extension type _Atomics._(JSObject _) implements JSObject {
  @JS('wait')
  external static JSString wait(JSInt32Array typedArray, int index, int value);

  @JS('wait')
  external static JSString waitWithTimeout(
      JSInt32Array typedArray, int index, int value, int timeOutInMillis);

  @JS()
  external static void notify(JSInt32Array typedArray, int index, [num count]);

  @JS()
  external static int store(JSInt32Array typedArray, int index, int value);

  @JS()
  external static int load(JSInt32Array typedArray, int index);
}

class Atomics {
  static const ok = 'ok';
  static const notEqual = 'not-equal';
  static const timedOut = 'timed-out';

  static bool get supported {
    return globalContext.has('Atomics');
  }

  static String wait(SafeI32Array typedArray, int index, int value) {
    return _Atomics.wait(typedArray.inner, index, value).toDart;
  }

  static String waitWithTimeout(
      SafeI32Array typedArray, int index, int value, int timeOutInMillis) {
    return _Atomics.waitWithTimeout(
            typedArray.inner, index, value, timeOutInMillis)
        .toDart;
  }

  static void notify(SafeI32Array typedArray, int index,
      [num count = double.infinity]) {
    _Atomics.notify(typedArray.inner, index, count);
  }

  static int store(SafeI32Array typedArray, int index, int value) {
    return _Atomics.store(typedArray.inner, index, value);
  }

  static int load(SafeI32Array typedArray, int index) {
    return _Atomics.load(typedArray.inner, index);
  }
}
