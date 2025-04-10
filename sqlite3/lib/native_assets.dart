/// Exports a variant of the native `sqlite3` library where symbols are resolved
/// through Dart's [native assets](https://github.com/dart-lang/sdk/issues/50565)
/// feature instead of through lookups with [DynamicLibrary].
///
/// At the moment, the use of [sqlite3Native] also requires a dependency on the
/// [sqlite3_native_assets](https://pub.dev/packages/sqlite3_native_assets)
/// package.
@experimental
library;

import 'dart:ffi';

export 'src/sqlite3_native_library.dart';

import 'package:meta/meta.dart';
import 'src/sqlite3_native_library.dart';
