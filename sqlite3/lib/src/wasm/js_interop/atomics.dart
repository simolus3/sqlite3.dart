import 'dart:typed_data';

import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS()
class Atomics {
  static const ok = 'ok';
  static const notEqual = 'not-equal';
  static const timedOut = 'timed-out';

  static bool get supported {
    return hasProperty(globalThis, 'Atomics');
  }

  @JS('wait')
  external static String wait(Int32List typedArray, int index, int value);

  @JS('wait')
  external static String waitWithTimeout(
      Int32List typedArray, int index, int value, int timeOutInMillis);

  @JS()
  external static void notify(Int32List typedArray, int index,
      [num count = double.infinity]);

  @JS()
  external static int store(Int32List typedArray, int index, int value);

  @JS()
  external static int load(Int32List typedArray, int index);
}
