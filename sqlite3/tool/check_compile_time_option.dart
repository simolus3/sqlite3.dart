import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Checks whether the loaded sqlite3 library includes a specific compile-time
/// option.
///
/// This is used to validate automated tests for this package around sqlite3
/// libraries compiled with different options (we want to make sure the options
/// are actually set).
///
/// Usage: `dart run tool/check_compile_time_option.dart options...`
void main(List<String> args) {
  final expectedOptions = args.toSet();
  sqlite3.compileOptions.forEach(expectedOptions.remove);

  if (expectedOptions.isNotEmpty) {
    print('Following compile-time options where not set: $expectedOptions');
    exit(1);
  }
}

typedef GetNative = Pointer<Uint8> Function(Int32 n);
typedef GetDart = Pointer<Uint8> Function(int n);
