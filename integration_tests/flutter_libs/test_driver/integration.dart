import 'dart:ffi';
import 'dart:io';

import 'package:flutter_driver/driver_extension.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/ffi/ffi.dart'
    show sqlite3_char, Utf8Utils, PointerUtils;
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
      final ptr = getCompileOption(i).cast<sqlite3_char>();

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
      ..closeWhenDone()
      ..execute('CREATE TABLE foo (bar)')
      ..execute('INSERT INTO foo VALUES (1), (2)');

    expect(db.select('SELECT * FROM foo'), [
      {'bar': 1},
      {'bar': 2},
    ]);
  });

  test('has json support', () {
    final db = sqlite3.openInMemory()..closeWhenDone();
    expect(db.select("SELECT json('[1,  2, 3]') AS r;"), [
      {'r': '[1,2,3]'},
    ]);
  });

  test('has fts5 support', () {});

  test('can create collation', () {
    final db = sqlite3.openInMemory()
      ..closeWhenDone()
      ..execute('CREATE TABLE foo2 (bar)')
      ..execute(
          "INSERT INTO foo2 VALUES ('AaAaaaAA'), ('BBBbBb'),('cCCCcc    '), ('  dD   ')");

    /// Create a collation to compare String without extra-blank to the right and
    /// ignoring case
    db.createCollation(
      name: "RTRIMNOCASE",
      function: (String? a, String? b) {
        // Combining nocase and rtrim
        //
        String? compareA = a?.toLowerCase().trimRight();
        String? compareB = b?.toLowerCase().trimRight();

        if (compareA == null && compareB == null) {
          return 0;
        } else if (compareA == null) {
          // a < b
          return -1;
        } else if (compareB == null) {
          // a > b
          return 1;
        } else {
          return compareA.compareTo(compareB);
        }
      },
    );

    expect(
        db.select(
            "SELECT * FROM foo2 WHERE bar = 'aaaaAaAa   ' COLLATE RTRIMNOCASE"),
        [
          {'bar': 'AaAaaaAA'},
        ]);

    expect(
        db.select(
            "SELECT * FROM foo2 WHERE bar = 'bbbbbb' COLLATE RTRIMNOCASE"),
        [
          {'bar': 'BBBbBb'},
        ]);

    expect(
        db.select(
            "SELECT * FROM foo2 WHERE bar = 'cCcccC' COLLATE RTRIMNOCASE"),
        [
          {'bar': 'cCCCcc    '},
        ]);

    expect(db.select("SELECT * FROM foo2 WHERE bar = 'dd' COLLATE RTRIMNOCASE"),
        []);
  });
}

extension on Database {
  void closeWhenDone() => addTearDown(dispose);
}
