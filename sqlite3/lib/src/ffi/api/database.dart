import 'dart:ffi';

import '../../common/database.dart';
import 'statement.dart';

/// An opened sqlite3 database with `dart:ffi`.
///
/// See [CommonDatabase] for the methods that are available on both the FFI and
/// the WebAssembly implementation.
abstract class Database implements CommonDatabase {
  /// The native database connection handle from sqlite.
  ///
  /// This returns a pointer towards the opaque sqlite3 structure as defined
  /// [here](https://www.sqlite.org/c3ref/sqlite3.html).
  Pointer<void> get handle;

  // override for more specific subtype
  @override
  PreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true, bool checkNoTail = false});

  @override
  List<PreparedStatement> prepareMultiple(String sql,
      {bool persistent = false, bool vtab = true});
}
