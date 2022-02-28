import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('BigInt')
external Object Function(String string) get _jsBigInt;

Object bigIntToJs(BigInt i) => _jsBigInt(i.toString());
BigInt jsToBigInt(Object jsObject) =>
    BigInt.parse(callMethod<String>(jsObject, 'toString', const []));
