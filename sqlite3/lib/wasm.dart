/// Experimental access to `sqlite3` on the web.
///
/// Using this library requires additional setup, see the readme of the
/// `sqlite3` package for details.
@experimental
library sqlite3.wasm;

import 'package:meta/meta.dart';

export 'common.dart' hide CommmonSqlite3;

export 'src/wasm/environment.dart';
export 'src/wasm/file_system.dart' hide LogFileSystems;
export 'src/wasm/sqlite3.dart';
