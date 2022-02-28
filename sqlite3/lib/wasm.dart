/// Experimental access to `sqlite3` on the web without Emscripten or any
/// external JavaScript libraries.
@experimental
library sqlite3.wasm;

import 'package:meta/meta.dart';

export 'common.dart' hide CommmonSqlite3;

export 'src/wasm/sqlite3.dart';
