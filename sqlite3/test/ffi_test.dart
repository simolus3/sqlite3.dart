import 'dart:ffi';

import 'package:test/test.dart';
import 'package:sqlite3/src/ffi/ffi.dart';

void main() {
  test('isNullPointer', () {
    expect(Pointer.fromAddress(1).isNullPointer, isFalse);
    expect(Pointer.fromAddress(0).isNullPointer, isTrue);
  });
}
