import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart';

import 'client.dart';
import 'worker.dart';

/// A [StorageMode], name pair representing an existing database already stored
/// by the current browsing context.
typedef ExistingDatabase = (StorageMode, String);

/// Types of files persisted for databases by virtual file system
/// implementations.
enum FileType {
  /// The main database file.
  database,

  /// A journal file used to synchronize changes toe database file.
  journal,
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

  /// Creates a remote exception from the [message] thrown.
  RemoteException({required this.message});

  @override
  String toString() {
    return 'Remote error: $message';
  }
}

abstract class FileSystem {
  StorageMode get storage;
  String get databaseName;

  Future<bool> exists(FileType type);
  Future<Uint8List> readFile(FileType type);
  Future<void> writeFile(FileType type, Uint8List content);
}

/// Abstraction over a database either available locally or in a remote worker.
abstract class Database {
  FileSystem get fileSystem;

  /// A relayed stream of [CommonDatabase.updates] from the remote worker.
  ///
  /// Updates are only sent across worker channels while a subscription to this
  /// stream is active.
  Stream<SqliteUpdate> get updates;

  /// Closes this database and instructs the worker to release associated
  /// resources.
  ///
  /// No methods may be called after a call to [dispose].
  Future<void> dispose();

  /// The rowid for the last insert operation made on this database.
  ///
  /// This calls [CommonDatabase.lastInsertRowId] in the worker.
  Future<int> get lastInsertRowId;

  /// The application-specific user version, mirroring
  /// [CommonDatabase.userVersion] being accessed in the remote worker.
  Future<int> get userVersion;
  Future<void> setUserVersion(int version);

  /// Prepares [sql] and executes it with the given [parameters].
  Future<void> execute(String sql, [List<Object?> parameters = const []]);

  /// Prepares [sql], executes it with the given [parameters] and returns the
  /// [ResultSet].
  Future<ResultSet> select(String sql, [List<Object?> parameters = const []]);

  /// Sends a custom request to the worker database.
  ///
  /// Custom requests are handled by implementing `handleCustomRequest` in your
  /// `WorkerDatabase` subclass.
  Future<JSAny?> customRequest(JSAny? request);
}

/// A connection from a client from the perspective of a worker.
abstract class ClientConnection {
  /// The unique id for this connection.
  int get id;

  /// A future that completes when the connection get closed, for instance
  /// because the owning tab is closed.
  Future<void> get closed;

  /// Sends a custom request __towards the client__. This is not currently
  /// implemented.
  Future<JSAny?> customRequest(JSAny? request);
}

/// A [CommonDatabase] wrapped with functionality to handle custom requests.
abstract class WorkerDatabase {
  /// The database made available to the worker.
  CommonDatabase get database;

  /// Handles a custom [request] (encoded as any JS value) from the
  /// [connection].
  ///
  /// The response is sent over the channel and completes a
  /// [Database.customRequest] call for clients.
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request);
}

/// A controller responsible for opening databases in the worker.
abstract base class DatabaseController {
  /// Loads a wasm module from the given [uri] with the specified [headers].
  Future<WasmSqlite3> loadWasmModule(Uri uri,
      {Map<String, String>? headers}) async {
    return WasmSqlite3.loadFromUrl(uri, headers: headers);
  }

  /// Opens a database in the pre-configured [sqlite3] instance under the
  /// specified [path] in the given [vfs].
  ///
  /// This should virtually always call `sqlite3.open(path, vfs: vfs)` and wrap
  /// the result in a [WorkerDatabase] subclass.
  Future<WorkerDatabase> openDatabase(
      WasmSqlite3 sqlite3, String path, String vfs);

  /// Handles custom requests from clients that are not bound to a database.
  ///
  /// This is not currently used.
  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request);
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
  final List<(StorageMode, AccessMode)> availableImplementations;

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

/// The result of [WebSqlite.connectToRecommended], containing the opened
/// [database] as well as the [FeatureDetectionResult] leading to that database
/// implementation being chosen.
final class ConnectToRecommendedResult {
  /// The opened [Database] hosted on another worker.
  final Database database;

  /// The missing or available browser features that lead to the current
  /// [storage] and [access] modes being selected.
  final FeatureDetectionResult features;

  /// The [StorageMode] storing contents for [database].
  final StorageMode storage;

  /// The [AccessMode] used to access teh [database] instance.
  final AccessMode access;

  ConnectToRecommendedResult({
    required this.database,
    required this.features,
    required this.storage,
    required this.access,
  });
}

/// Provides asynchronous access to databases hosted in web workers.
///
/// Please see the readme of the `sqlite3_web` package for an overview on how
/// to set up and use this package.
abstract class WebSqlite {
  /// Tries to find features related to storing and accessing databases.
  ///
  /// The [databaseName] can optionally be used to make
  /// [FeatureDetectionResult.existingDatabases] more reliable, as IndexedDB
  /// databases are not found otherwise.
  Future<FeatureDetectionResult> runFeatureDetection({String? databaseName});

  /// Connects to a database identified by its [name] stored under [type] and
  /// accessed via the given [access] mode.
  Future<Database> connect(String name, StorageMode type, AccessMode access);

  /// Starts a feature detection via [runFeatureDetection] and then [connect]s
  /// to the best database available.
  Future<ConnectToRecommendedResult> connectToRecommended(String name);

  /// Entrypoints for workers hosting datbases.
  static void workerEntrypoint({
    required DatabaseController controller,
  }) {
    WorkerRunner(controller).handleRequests();
  }

  /// Opens a [WebSqlite] instance by connecting to the given [worker] and
  /// using the [wasmModule] url to load sqlite3.
  static WebSqlite open({
    required Uri worker,
    required Uri wasmModule,
  }) {
    return DatabaseClient(worker, wasmModule);
  }
}
