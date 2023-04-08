/// Experimental access to `sqlite3` on the web.
///
/// Using this library requires additional setup, see the readme of the
/// `sqlite3` package for details.
///
/// Also, please note that this library is not production-ready at the moment
/// and should be used with caution.
/// In particular, the implementation of the virtual file system used to store
/// persistent databases may change in a way that requires migration work in the
/// future.
///
/// As long as this library is marked as experimental, it is not subject to
/// semantic versioning.
@experimental
library sqlite3.wasm;

import 'package:meta/meta.dart';

export 'common.dart' hide CommmonSqlite3;

export 'src/wasm/environment.dart';
export 'src/wasm/file_system.dart' hide debugFileSystem;
export 'src/wasm/file_system/indexed_db.dart'
    hide AsynchronousIndexedDbFileSystem;
export 'src/wasm/file_system/opfs.dart' show OpfsFileSystem;
export 'src/wasm/sqlite3.dart';
