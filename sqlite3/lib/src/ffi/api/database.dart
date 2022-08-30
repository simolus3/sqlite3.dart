import 'dart:ffi';

import '../../common/database.dart';
import 'statement.dart';

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

  /// Create a backup of the current database (this) into another database
  /// ([toDatabase]) on memory or disk.
  ///
  /// The returned stream returns a rough estimate on the progress of the
  /// backup, as a fraction between `0` and `1`. No progress is reported if
  /// either this or [toDatabase] is an in-memory database.
  ///
  /// To simply await the backup operation as a future, call [Stream.drain] on
  /// the returned stream.
  ///
  /// See https://www.sqlite.org/c3ref/backup_finish.html
  Stream<double> backup(Database toDatabase);
}
