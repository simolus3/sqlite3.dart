import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../../compile_options.dart';
import '../../platform/web.dart';

@JS('BigInt')
external JSBigInt _bigInt(JSAny? s);

@JS('Number')
external JSNumber _number(JSAny? obj);

@JS('Number.isSafeInteger')
external JSBoolean _numberIsSafeInteger(JSAny? obj);

extension type WrappedJSAny._(JSAny _) implements JSAny {
  external static JSArray<JSAny?> keys(JSObject o);

  @JS('toString')
  external JSString _toString();
}

@JS('Object')
extension type WrappedJSObject._(JSObject _) implements JSObject {
  external static JSArray<JSAny?> keys(JSObject o);
}

/// The range of integers a JavaScript number represents exactly
/// (`Number.MIN_SAFE_INTEGER` to `Number.MAX_SAFE_INTEGER`).
const _maxSafeInteger = 9007199254740991;
const _minSafeInteger = -9007199254740991;

extension type JsBigInt(JSBigInt _jsBigInt) implements JSBigInt {
  factory JsBigInt.parse(String s) => JsBigInt(_bigInt(s.toJS));

  /// Creates a JavaScript `BigInt` holding exactly [i].
  ///
  /// A Dart `int` outside the safe integer range of a JavaScript number (on
  /// dart2wasm, where ints are 64 bits) is converted through its decimal
  /// representation, because `i.toJS` would round it to the nearest double.
  factory JsBigInt.fromInt(int i) {
    if (i >= _minSafeInteger && i <= _maxSafeInteger) {
      return JsBigInt(_bigInt(i.toJS));
    }
    return JsBigInt.parse(i.toString());
  }

  factory JsBigInt.fromBigInt(BigInt i) => JsBigInt.parse(i.toString());

  /// This value as a Dart `int`.
  ///
  /// On dart2wasm, where a Dart `int` is a 64-bit integer, a value outside
  /// the safe integer range of a JavaScript number is converted exactly
  /// through its decimal representation (converting it through a JavaScript
  /// number would round it to the nearest double). On dart2js, where a Dart
  /// `int` is a JavaScript number, such a value cannot be represented exactly
  /// either way; use [asDartBigInt] there.
  int get asDartInt {
    final number = _number(_jsBigInt);
    if (_numberIsSafeInteger(number).toDart) {
      return number.toDartInt;
    }
    return int.parse(jsToString());
  }

  Object get asDartBigInt {
    if (!supportDartBigInts) {
      return BoxedJavaScriptBigInt(this);
    }

    return BigInt.parse(jsToString());
  }

  JSBigInt get jsObject => _jsBigInt;

  bool get isSafeInteger => _numberIsSafeInteger(_number(_jsBigInt)).toDart;

  Object toDart() {
    return isSafeInteger ? asDartInt : asDartBigInt;
  }

  String jsToString() {
    return (_jsBigInt as WrappedJSAny)._toString().toDart;
  }
}

extension type IteratorResult<T extends JSAny?>(JSObject _)
    implements JSObject {
  external JSBoolean? get done;
  external T? get value;
}

extension type AsyncIterator<T extends JSAny?>(JSObject _) implements JSObject {
  external JSPromise<IteratorResult<T>> next();
}

@JS('Symbol.asyncIterator')
external JSSymbol get _asyncIterator;

/// Exposes the async iterable interface as a Dart stream.
///
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Iteration_protocols#the_async_iterator_and_async_iterable_protocols
class AsyncJavaScriptIteratable<T extends JSAny?> extends Stream<T> {
  final JSObject _jsObject;

  AsyncJavaScriptIteratable(this._jsObject) {
    if (!_jsObject.hasProperty(_asyncIterator).toDart) {
      throw ArgumentError(
        'Target object does not implement the async iterable '
        'interface',
      );
    }
  }

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final iterator = _jsObject.callMethod<AsyncIterator<T>>(_asyncIterator);
    final controller = StreamController<T>(sync: true);
    JSPromise<IteratorResult<T>>? currentlyPendingPromise;

    void fetchNext() {
      assert(currentlyPendingPromise == null);
      final promise = currentlyPendingPromise = iterator.next();

      promise.toDart.then((result) {
        final done = result.done?.toDart ?? false;
        final value = result.value;

        if (done) {
          controller.close();

          currentlyPendingPromise = null;
        } else {
          controller.add(value as T);

          currentlyPendingPromise = null;
          if (!controller.isPaused) {
            fetchNext();
          }
        }
      }, onError: controller.addError);
    }

    void fetchNextIfNecessary() {
      if (currentlyPendingPromise == null && !controller.isPaused) {
        fetchNext();
      }
    }

    controller
      ..onListen = fetchNext
      ..onResume = fetchNextIfNecessary;

    return controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}
