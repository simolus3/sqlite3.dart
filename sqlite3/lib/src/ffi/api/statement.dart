import 'dart:ffi';

import '../../common/statement.dart';

/// A prepared statement.
abstract class PreparedStatement implements CommonPreparedStatement {
  /// The underlying `sqlite3_stmt` pointer.
  ///
  /// Obtains the raw [statement](https://www.sqlite.org/c3ref/stmt.html) from
  /// the sqlite3 C-api that this [PreparedStatement] wraps.
  Pointer<void> get handle;
}
