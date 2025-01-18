/// Exports common interfaces that are implemented by both the `dart:ffi` and
/// the `dart:js` WASM version of this library.
library;

export 'src/constants.dart';
export 'src/database.dart';
export 'src/exception.dart';
export 'src/functions.dart';
export 'src/in_memory_vfs.dart' show InMemoryFileSystem;
export 'src/jsonb.dart';
export 'src/result_set.dart';
export 'src/sqlite3.dart';
export 'src/statement.dart'
    show CommonPreparedStatement, StatementParameters, CustomStatementParameter;
export 'src/vfs.dart';
