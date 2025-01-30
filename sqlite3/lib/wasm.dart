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
/// {@category wasm}
library;

export 'common.dart';

export 'src/wasm/vfs/simple_opfs.dart' show SimpleOpfsFileSystem;
export 'src/wasm/vfs/indexed_db.dart' show IndexedDbFileSystem;
export 'src/wasm/vfs/async_opfs/client.dart' show WasmVfs;
export 'src/wasm/vfs/async_opfs/worker.dart' show WorkerOptions, VfsWorker;
export 'src/wasm/sqlite3.dart';
