import 'dart:ffi';
import 'dart:io';

import 'package:flutter_driver/driver_extension.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  enableFlutterDriverExtension();

  setUpAll(() async {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();

    open.overrideFor(
        OperatingSystem.android, () => DynamicLibrary.open('libsqlcipher.so'));
  });

  tearDownAll(() {
    // See https://github.com/flutter/flutter/issues/12427#issuecomment-464449765
    Future.delayed(const Duration(milliseconds: 500)).then((_) => exit(0));
  });

  test('can open sqlite3', () {
    print(sqlite3.version);
  });

  test('contains sqlite3_key function', () {
    expect(open.openSqlite().lookup('sqlite3_key'),
        isA<Pointer>().having((e) => e.address, 'address', isPositive));
  });
}
