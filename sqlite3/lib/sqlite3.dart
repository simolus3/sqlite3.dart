/// Dart bindings to `sqlite3`.
///
/// {@category native}
/// {@category hook}
library;

// Hide common base classes that have more specific ffi-APIs.
export 'common.dart' hide CommonPreparedStatement, CommonDatabase;

export 'src/ffi/api.dart';

export 'src/ffi/pool/leased_database.dart' show LeasedDatabase;
export 'src/ffi/pool/pool.dart' hide PoolImplementation;
export 'src/ffi/pool/shared.dart' hide RemotePool;
