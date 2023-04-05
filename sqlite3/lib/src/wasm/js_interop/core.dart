import 'dart:async';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('BigInt')
external Object _bigInt(Object s);

@JS('Number')
external int _number(Object obj);

@JS('self')
external JsContext get self;

@JS()
@staticInterop
class JsContext {}

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

@JS('Symbol.asyncIterator')
external Object get _asyncIterator;

/// Exposes the async iterable interface as a Dart stream.
///
/// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Iteration_protocols#the_async_iterator_and_async_iterable_protocols
class AsyncJavaScriptIteratable<T> extends Stream<T> {
  final Object _jsObject;

  AsyncJavaScriptIteratable(this._jsObject) {
    if (!hasProperty(_jsObject, _asyncIterator)) {
      throw ArgumentError('Target object does not implement the async iterable '
          'interface');
    }
  }

  @override
  StreamSubscription<T> listen(void Function(T event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    final iteratorFn = getProperty<Object>(_jsObject, _asyncIterator);
    final iterator =
        callMethod<Object Function()>(iteratorFn, 'bind', [_jsObject])();

    final controller = StreamController<T>(sync: true);
    Object? currentlyPendingPromise;

    void fetchNext() {
      assert(currentlyPendingPromise == null);
      final promise =
          currentlyPendingPromise = callMethod<Object>(iterator, 'next', []);

      promiseToFuture<Object>(promise).then(
        (result) {
          final done = getProperty<bool?>(result, 'done') ?? false;
          final value = getProperty<Object?>(result, 'value');

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
        },
        onError: controller.addError,
      );
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
