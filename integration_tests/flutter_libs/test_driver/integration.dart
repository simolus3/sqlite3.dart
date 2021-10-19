import 'dart:ffi';
import 'dart:io';

import 'package:flutter_driver/driver_extension.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/ffi/ffi.dart' show char, Utf8Utils, PointerUtils;
import 'package:sqlite3/open.dart';

typedef _sqlite3_compileoption_get_native = Pointer<Uint8> Function(Int32 n);
typedef _sqlite3_compileoption_get_dart = Pointer<Uint8> Function(int n);

void main() {
  enableFlutterDriverExtension();

  tearDownAll(() {
    // See https://github.com/flutter/flutter/issues/12427#issuecomment-464449765
    Future.delayed(const Duration(milliseconds: 500)).then((_) => exit(0));
  });

  test('can open sqlite3', () {
    print(sqlite3.version);

    final getCompileOption = open.openSqlite().lookupFunction<
        _sqlite3_compileoption_get_native,
        _sqlite3_compileoption_get_dart>('sqlite3_compileoption_get');

    String? lastOption;
    var i = 0;
    do {
      final ptr = getCompileOption(i).cast<char>();

      if (!ptr.isNullPointer) {
        lastOption = ptr.readString();
        print('Compile-option: $lastOption');
      } else {
        lastOption = null;
      }

      i++;
    } while (lastOption != null);
  });

  test('can open databases', () {
    final db = sqlite3.openInMemory()
      ..execute('CREATE TABLE foo (bar)')
      ..execute('INSERT INTO foo VALUES (1), (2)');

    expect(db.select('SELECT * FROM foo'), [
      {'bar': 1},
      {'bar': 2},
    ]);
  });
}
