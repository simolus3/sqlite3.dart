import 'dart:typed_data';
import 'package:sqlite3/common.dart';

/// A [StorageMode], name pair representing an existing database already stored
/// by the current browsing context.
typedef ExistingDatabase = (StorageMode, String);

/// Types of files persisted for databases by virtual file system
/// implementations.
enum FileType {
  /// The main database file.
  database,

  /// A journal file used to synchronize changes on the database file.
  journal,
}

/// An implemented mechanism to use SQLite on the web.
///
/// Due to the large variety of browsers and the web standards they support,
/// a number of implementations are available. The most important are:
///
///  - [opfsShared]: Only available on Firefox, but very efficient.
///  - [opfsWithExternalLocks]: Only available on recent Chrome versions, also
///    quite efficient.
///  - [opfsAtomics]: Only available when using COEP and COOP headers, but also
///    reasonably efficient and supported across browsers.
///  - [indexedDbShared]: A less efficient IndexedDB-based implementation used
///    as a fallback on older Chrome versions.
///
/// All other options are not recommended, but may be selected if there's no
/// better option (e.g. older Chrome versions on Android may use
/// [indexedDbUnsafeWorker]).
enum DatabaseImplementation {
  /// Host an in-memory database in the current tab.
  ///
  /// This isn't really useful outside of tests.
  inMemoryLocal(StorageMode.inMemory, AccessMode.inCurrentContext),

  /// Host an in-memory database in a shared worker.
  ///
  /// This isn't really useful outside of tests.
  inMemoryShared(StorageMode.inMemory, AccessMode.throughSharedWorker),

  /// Open an IndexedDB database with a dedicated worker per tab.
  ///
  /// There is no concurrency control between these tabs, so this effectively
  /// does not support multiple tabs. It's mostly included for legacy reasons.
  indexedDbUnsafeLocal(StorageMode.indexedDb, AccessMode.inCurrentContext),

  /// Open an IndexedDB database with a dedicated worker per tab.
  ///
  /// There is no concurrency control between these tabs, so this effectively
  /// does not support multiple tabs. It's mostly included for legacy reasons.
  indexedDbUnsafeWorker(
      StorageMode.indexedDb, AccessMode.throughDedicatedWorker),

  /// Open an IndexedDB database in a shared worker.
  indexedDbShared(StorageMode.indexedDb, AccessMode.throughSharedWorker),

  /// Open an synchronous database stored in OPFS.
  ///
  /// The database is opened with the non-standard `readwrite-unsafe` option,
  /// and the web locks API is used to ensure two tabs don't access the same
  /// database concurrently.
  opfsWithExternalLocks(StorageMode.opfs, AccessMode.throughDedicatedWorker),

  /// Open an asynchronous database stored in OPFS. It is "syncified" by using
  /// a pair of two dedicated workers implementing an RPC channel over shared
  /// memory and atomics.
  opfsAtomics(StorageMode.opfs, AccessMode.throughDedicatedWorker),

  /// Open a synchronous database stored in OPFS.
  ///
  /// This works by letting a shared worker spawn a dedicated worker. This is
  /// supposed to work, but only implemented in Firefox.
  opfsShared(StorageMode.opfs, AccessMode.throughSharedWorker),
  ;

  final StorageMode storage;
  final AccessMode access;

  const DatabaseImplementation(this.storage, this.access);
}

/// Available locations to store database content in browsers.
enum StorageMode {
  // Note: Indices in this enum are used in the protocol, changing them is a
  // backwards-incompatible change.
  /// A origin-private folder provided by the file system access API.
  ///
  /// This is generally considered to be the most reliable way to store large
  /// data efficiently.
  opfs,

  /// A virtual file system implemented by splitting files into chunks which are
  /// then stored in IndexedDB.
  ///
  /// As sqlite3 expects a synchronous file system and IndexedDB is
  /// asynchronous, we maintain the illusion if synchronous access by keeping
  /// the entire database cached in memory and then flushing changes
  /// asynchronously.
  /// This technically looses durability, but is reasonably reliable in
  /// practice.
  indexedDb,

  /// Don't persist databases, instead keeping them in memory only.
  inMemory,
}

/// In addition to the [StorageMode] describing which browser API is used to
/// store content, this enum describes how databases are accessed.
enum AccessMode {
  /// Access databases by spawning a shared worker shared across tabs.
  ///
  /// This is more efficient as it avoids synchronization conflicts between tabs
  /// which may slow things down.
  throughSharedWorker,

  /// Access databases by spawning a dedicated worker for this tab.
  throughDedicatedWorker,

  /// Access databases without any shared or dedicated worker.
  inCurrentContext,
}

/// An exception thrown when a operation fails on the remote worker.
///
/// As the worker and the main tab have been compiled independently and don't
/// share a class hierarchy or object representations, it is impossible to send
/// typed exception objects. Instead, this exception wraps every error or
/// exception thrown by the remote worker and contains the [toString]
/// representation in [message].
final class RemoteException implements Exception {
  /// The [Object.toString] representation of the original exception.
  final String message;

  /// The exception that happened in the context running the operation.
  ///
  /// Since that context may be a web worker which can't send arbitrary Dart
  /// objects to us, only a few common exception types are recognized and
  /// serialized.
  /// At the moment, this only includes [SqliteException].
  final Object? exception;

  /// Creates a remote exception from the [message] thrown.
  const RemoteException({required this.message, this.exception});

  @override
  String toString() {
    return 'Remote error: $message';
  }
}

/// An exception thrown when the remote end accepts an abort requeset sent for a
/// previous request.
final class AbortException extends RemoteException {
  const AbortException() : super(message: 'Operation was cancelled');
}

/// A virtual file system used by a worker to persist database files.
abstract class FileSystem {
  /// Returns whether a database file identified by its [type] exists.
  Future<bool> exists(FileType type);

  /// Reads the database file (or its journal).
  Future<Uint8List> readFile(FileType type);

  /// Replaces the database file (or its journal), creating the virtual file if
  /// it doesn't exist.
  Future<void> writeFile(FileType type, Uint8List content);

  /// If the file system hosting the database in the worker is not synchronous,
  /// flushes pending writes.
  Future<void> flush();
}

/// An enumeration of features not supported by the current browsers.
///
/// While this information may not be useful to end users, it can be used to
/// understand why a particular file system implementation is unavailable.
enum MissingBrowserFeature {
  /// The browser is missing support for [shared workers].
  ///
  /// [shared workers]: https://developer.mozilla.org/en-US/docs/Web/API/SharedWorker
  sharedWorkers,

  /// The browser is missing support for [web workers] in general.
  ///
  /// [web workers]: https://developer.mozilla.org/en-US/docs/Web/API/Worker
  dedicatedWorkers,

  /// The browser doesn't allow shared workers to spawn dedicated workers in
  /// their context.
  ///
  /// While the specification for web workers explicitly allows this, this
  /// feature is only implemented by Firefox at the time of writing.
  dedicatedWorkersInSharedWorkers,

  /// The browser doesn't allow dedicated workers to spawn their own dedicated
  /// workers.
  dedicatedWorkersCanNest,

  /// The browser does not support a synchronous version of the [File System API]
  ///
  /// [File System API]: https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API
  fileSystemAccess,

  /// The browser does not support the (non-standard) `readwrite-unsafe` open
  /// mode proposed in https://github.com/whatwg/fs/blob/main/proposals/MultipleReadersWriters.md#modes-of-creating-a-filesystemsyncaccesshandle.
  createSyncAccessHandleReadWriteUnsafe,

  /// The browser does not support IndexedDB.
  indexedDb,

  /// The browser does not support shared array buffers and `Atomics.wait`.
  ///
  /// To enable this feature in most browsers, you need to serve your app with
  /// two [special headers](https://web.dev/coop-coep/).
  sharedArrayBuffers,
}

/// The result of [WebSqlite.runFeatureDetection], describing which browsers
/// and databases are available in the current browser.
final class FeatureDetectionResult {
  /// A list of features that were probed and found to be unsupported in the
  /// current browser.
  final List<MissingBrowserFeature> missingFeatures;

  /// All existing databases that have been found.
  ///
  /// Databases are only found reliably when a database name is passed to
  /// [WebSqlite.runFeatureDetection].
  final List<ExistingDatabase> existingDatabases;

  /// All available [StorageMode], [AccessMode] pairs describing the databases
  /// supported by this browser.
  final List<DatabaseImplementation> availableImplementations;

  FeatureDetectionResult({
    required this.missingFeatures,
    required this.existingDatabases,
    required this.availableImplementations,
  });

  @override
  String toString() {
    return 'Existing: $existingDatabases, available: '
        '$availableImplementations, missing: $missingFeatures';
  }
}
