import 'dart:ffi';

import 'package:meta/meta.dart';

import 'ffi/api.dart';
import 'ffi/implementation.dart';

/// A version of [sqlite3] that uses FFI bindings backed by [native assets]
/// instead of opening a [DynamicLibrary].
///
/// When used together with the `sqlite3_native_assets` package, using these
/// bindings guarantees that a version of the SQLite library is included with
/// your app. This means that `sqlite3_flutter_libs` is no longer required.
/// Also, this build works on all Dart platforms and does not require Flutter.
///
/// Using these bindings is experimental (since native assets in Dart are an
/// experimental feature).
///
/// [native assets](https://dart.dev/interop/c-interop#native-assets)
@experimental
final Sqlite3 sqlite3Native = FfiSqlite3.nativeAssets();
