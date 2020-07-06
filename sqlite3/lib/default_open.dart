/// Util library to open `sqlite3` across Desktop operating systems.
library default_open;

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

DynamicLibrary _openSqlite3() {
  if (Platform.isWindows) {
    return DynamicLibrary.open('sqlite3.dll');
  } else if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('/usr/lib/libsqlite3.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libsqlite3.so');
  }

  throw Exception('sqlite3 is not available on the current platform');
}

/// Opens `sqlite3` bindings based on some simple platform-specific rules.
Sqlite3 defaultOpen() => Sqlite3(_openSqlite3());
