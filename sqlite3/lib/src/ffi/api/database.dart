import 'dart:ffi';

import '../../common/database.dart';
import 'statement.dart';

typedef BackupProgressCallback = void Function(double progress);

/// An opened sqlite3 database with `dart:ffi`.
///
/// See [CommonDatabase] for the methods that are available on both the FFI and
/// the WebAssembly implementation.
abstract class Database extends CommonDatabase {
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

  /// Create a backup of the current database into another database
  /// on memory or disk
  /// See https://www.sqlite.org/c3ref/backup_finish.html
  void backup(Database toDatabase, {BackupProgressCallback? progressCallback});
}
