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

  /// Loads a [run-time loadable extension][loadext doc] for this database.
  ///
  /// The [sharedLibrary] is either the name or the full path of the extension
  /// to load. sqlite will try to append OS-specific suffixes to the path if the
  /// extension couldn't be found otherwise.
  /// The optional [entrypoint] argument can be used to supply the name of the
  /// entry point C function for the extension. When set to `null` (the default),
  /// sqlite3 will attempt to infer the correct entrypoint.
  ///
  /// __NOTICE AND SECURITY INFORMATION__: In sqlite3, dynamically loading
  /// extensions is disabled by default. Ideally, one would enable loading
  /// extensions with the `sqlite3_db_config` C function, which only enables
  /// loading extensions through sqlite3's C API. However, that configuration
  /// function is variadic in C, which means that it can't be called via
  /// `dart:ffi` yet.
  /// Instead, this function uses `sqlite3_enable_load_extension`, which, in
  /// addition to enabling extension loading through the C API, also enables the
  /// `load_extension` SQL function, which is a security risk for applications
  /// running untrusted SQL statements.
  /// For this reason, this function will only enable extension loading
  /// temporarily and immediately disable it after the extension has been
  /// loaded. In other words, regardless of whether loading extensions has been
  /// enabled before calling [loadExtension], it will be disabled afterwards.
  ///
  /// [loadext doc]: https://www.sqlite.org/loadext.html
  void loadExtension(String sharedLibrary, [String? entrypoint]);
}
