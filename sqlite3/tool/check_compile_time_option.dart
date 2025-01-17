import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/src/ffi/memory.dart';
import 'package:sqlite3/src/ffi/sqlite3.g.dart';

/// Checks whether the loaded sqlite3 library includes a specific compile-time
/// option.
///
/// This is used to validate automated tests for this package around sqlite3
/// libraries compiled with different options (we want to make sure we're
/// the options are actually set).
///
/// Usage: `dart run tool/check_compile_time_option.dart options...`
void main(List<String> args) {
  final getCompileOption = open
      .openSqlite()
      .lookupFunction<GetNative, GetDart>('sqlite3_compileoption_get');

  Iterable<String> compileTimeOptions() sync* {
    String? lastOption;
    var i = 0;

    do {
      final ptr = getCompileOption(i).cast<sqlite3_char>();

      if (!ptr.isNullPointer) {
        lastOption = ptr.readString();
        yield lastOption;
      } else {
        lastOption = null;
      }

      i++;
    } while (lastOption != null);
  }

  final expectedOptions = args.toSet();
  compileTimeOptions().forEach(expectedOptions.remove);

  if (expectedOptions.isNotEmpty) {
    print('Following compile-time options where not set: $expectedOptions');
    exit(1);
  }
}

typedef GetNative = Pointer<Uint8> Function(Int32 n);
typedef GetDart = Pointer<Uint8> Function(int n);
