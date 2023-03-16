import 'dart:typed_data';

import '../implementation/sqlite3.dart';
import '../sqlite3.dart';
import 'bindings.dart';
import 'environment.dart';
import 'wasm_interop.dart';

/// A WebAssembly version of the [CommmonSqlite3] interface.
///
/// This implementation supports the same API as the native version based on
/// `dart:ffi`, but runs in the web.
class WasmSqlite3 extends Sqlite3Implementation {
  /// Loads a web version of the sqlite3 libraries.
  ///
  /// [source] must be a byte buffer of a `sqlite.wasm` file prepared for this
  /// package. This file can be obtained at the [releases][pgk release] for this
  /// package.
  ///
  /// The [environment] can optionally be set to use a custom virtual file
  /// system. By default, all databases opened are stored in memory only (this
  /// includes databases opened with a path in [open]).
  ///
  /// [pgk release]: https://github.com/simolus3/sqlite3.dart/releases
  static Future<WasmSqlite3> load(Uint8List source,
      [SqliteEnvironment? environment]) {
    return WasmBindings.instantiateAsync(
            source, environment ?? SqliteEnvironment())
        .then(WasmSqlite3._);
  }

  WasmSqlite3._(WasmBindings bindings) : super(WasmSqliteBindings(bindings));
}
