import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('BigInt')
external Object _jsBigInt(String s);

@JS('Number')
external int _jsNumber(Object obj);

@JS('eval')
external Object _eval(String s);

bool Function(Object, Object) jsLeq =
    _eval('(a, b) => a <= b') as bool Function(Object, Object);

Object bigIntToJs(BigInt i) => _jsBigInt(i.toString());
BigInt jsToBigInt(Object jsObject) =>
    BigInt.parse(callMethod<String>(jsObject, 'toString', const []));
int jsBigIntToNum(Object jsObject) => _jsNumber(jsObject);
