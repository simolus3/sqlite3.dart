import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:sqlite3/wasm.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web/web.dart'
    show
        AbortSignal,
        DedicatedWorkerGlobalScope,
        EventStreamProviders,
        FileSystemDirectoryHandle,
        FileSystemFileHandle,
        FileSystemSyncAccessHandle,
        AbortController;
// ignore: implementation_imports
import 'package:sqlite3/src/wasm/js_interop/new_file_system_access.dart';

import 'database.dart';
import 'channel.dart';
import 'locks.dart';
import 'protocol.dart';
import 'shared.dart';
import 'types.dart';
import 'worker_connector.dart';

extension on WorkerEnvironment {
  /// Messages outside of a connection being posted to the worker or a connect
  /// port of a shared worker.
  ///
  /// We're not using them for actual channels, but instead have clients
  /// setup message ports which are then forwarded to workers using these
  /// top-level requests.
  Stream<Message> get topLevelRequests {
    return incomingMessages.map((event) {
      return event.data as Message;
    });
  }
}

class _StreamState {
  StreamSubscription<void>? subscription;

  void cancel() {
    subscription?.cancel();
    subscription = null;
  }
}

/// A database opened by a client.
final class _ConnectionDatabase {
  final DatabaseState database;
  final int id;

  final _StreamState updates = _StreamState();
  final _StreamState rollbacks = _StreamState();
  final _StreamState commits = _StreamState();

  /// If the connection currently holds a lock on the database, this contains
  /// an id assigned to that lock and a completer to release it.
  (int, Completer<void>)? _heldLock;
  int _nextLockId = 1;
  final List<AbortController> _activeAbortableOperations = [];

  _ConnectionDatabase(this.database, [int? id]) : id = id ?? database.id;

  Future<void> close() async {
    updates.cancel();
    rollbacks.cancel();
    commits.cancel();

    for (final signal in _activeAbortableOperations) {
      signal.abort();
    }
    _activeAbortableOperations.clear();

    _heldLock?.$2.complete();
    await database.decrementRefCount();
  }

  AbortController _startAbortableOperation(AbortSignal parent) {
    final controller = AbortController();
    parent.onabort = (() => controller.abort()).toJS;
    _activeAbortableOperations.add(controller);
    return controller;
  }

  void _removeAbortableOperation(AbortController controller) {
    _activeAbortableOperations.remove(controller);
  }

  Future<T> useLock<T>(
    int? lockId,
    AbortSignal abortSignal,
    T Function() block,
  ) {
    if (lockId == null) {
      // Not in an explicit lock context, just use global database lock.
      if (!database.locks.canRunSynchronousBlockDirectly) {
        final started = _startAbortableOperation(abortSignal);
        return database.locks.lock(block, started.signal).whenComplete(() {
          _removeAbortableOperation(started);
        });
      }
    } else {
      if (_heldLock?.$1 != lockId) {
        throw StateError('Requested operation on inactive lock state.');
      }
    }

    // Can run synchronous block directly.
    return Future.sync(block);
  }

  Future<int> obtainLockAsync(AbortSignal abortSignal) {
    final started = _startAbortableOperation(abortSignal);
    final resolvedLockId = Completer<int>();

    database.locks
        .lock(() {
          // Since we just obtained an exclusive lock, we cannot possibly be holding
          // the lock already.
          assert(_heldLock == null);

          final id = _nextLockId++;
          final completer = Completer<void>();
          _heldLock = (id, completer);
          resolvedLockId.complete(id);
          return completer.future;
        }, started.signal)
        .onError<Object>((e, s) {
          if (!resolvedLockId.isCompleted) {
            resolvedLockId.completeError(e, s);
          }
        });

    return resolvedLockId.future.whenComplete(() {
      _removeAbortableOperation(started);
    });
  }

  void releaseLock(int id) {
    if (_heldLock?.$1 != id) {
      throw StateError('Lock to be released is not active.');
    }

    _heldLock!.$2.complete();
    _heldLock = null;
  }
}

final class _ClientConnection extends ProtocolChannel
    implements ClientConnection {
  final WorkerRunner _runner;
  final List<_ConnectionDatabase> _openedDatabases = [];

  @override
  final int id;

  _ClientConnection({
    required WorkerRunner runner,
    required StreamChannel<Message> channel,
    required this.id,
  }) : _runner = runner,
       super(channel) {
    closed.whenComplete(() async {
      for (final id in _openedDatabases) {
        await id.close();
      }
      _openedDatabases.clear();
    });
  }

  Future<Response> _handleCompatibilityCheck(
    CompatibilityCheck request,
    AbortSignal abortSignal,
  ) async {
    return newSimpleSuccessResponse(
      response: (await _runner.checkCompatibility(request)).toJS,
      requestId: request.requestId,
    );
  }

  @override
  FutureOr<Response> handleDedicatedCompatibilityCheck(
    DedicatedCompatibilityCheck request,
    AbortSignal abortSignal,
  ) {
    return _handleCompatibilityCheck(request, abortSignal);
  }

  @override
  FutureOr<Response> handleDedicatedInSharedCompatibilityCheck(
    DedicatedInSharedCompatibilityCheck request,
    AbortSignal abortSignal,
  ) {
    return _handleCompatibilityCheck(request, abortSignal);
  }

  @override
  FutureOr<Response> handleSharedCompatibilityCheck(
    SharedCompatibilityCheck request,
    AbortSignal abortSignal,
  ) {
    return _handleCompatibilityCheck(request, abortSignal);
  }

  @override
  Future<Response> handleConnect(
    ConnectRequest request,
    AbortSignal abortSignal,
  ) async {
    // This is only used to let clients connect to a dedicated worker hosted in
    // this shared worker.
    final inner = _runner._innerWorker!;
    newConnectRequest(
      endpoint: request.endpoint,
      requestId: 0,
      databaseId: null,
    ).sendToWorker(inner);

    return newSimpleSuccessResponse(
      response: null,
      requestId: request.requestId,
    );
  }

  @override
  Future<Response> handleCustom(
    CustomRequest request,
    AbortSignal abortSignal,
  ) async {
    JSAny? response;

    if (request.databaseId case final id?) {
      response = await (await _databaseById(
        id,
      ).database.opened).handleCustomRequest(this, request.payload);
    } else {
      response = await _runner._controller.handleCustomRequest(
        this,
        request.payload,
      );
    }

    return newSimpleSuccessResponse(
      requestId: request.requestId,
      response: response,
    );
  }

  @override
  Future<Response> handleOpen(
    OpenRequest request,
    AbortSignal abortSignal,
  ) async {
    await _runner.loadWasmModule(Uri.parse(request.wasmUri));
    DatabaseState? database;
    _ConnectionDatabase? connectionDatabase;

    try {
      database = _runner.findDatabase(
        request.databaseName,
        FileSystemImplementation.fromJS(request.storageMode),
        request.additionalData,
      );

      await (request.onlyOpenVfs ? database.vfs : database.opened);

      connectionDatabase = _ConnectionDatabase(database);
      _openedDatabases.add(connectionDatabase);

      return newSimpleSuccessResponse(
        response: database.id.toJS,
        requestId: request.requestId,
      );
    } catch (e) {
      if (database != null) {
        _openedDatabases.remove(connectionDatabase);
        await database.decrementRefCount();
      }

      rethrow;
    }
  }

  @override
  Future<Response> handleRunQuery(
    RunQuery request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    final openedDatabase = await database.database.opened;

    return database.useLock(request.lockId, abortSignal, () {
      final db = openedDatabase.database;

      if (request.checkInTransaction && db.autocommit) {
        throw StateError('Database is not in a transaction');
      }

      final parameters = TypeCode.decodeValues(
        request.parameters,
        request.typeVector,
      );

      ResultSet? resultSet;
      if (request.returnRows) {
        resultSet = db.select(request.sql, parameters);

        return RowsResponseUtils.wrapResultSet(
          request.requestId,
          resultSet: resultSet,
          autoCommit: db.autocommit,
          lastInsertRowId: db.lastInsertRowId,
        );
      } else {
        db.execute(request.sql, parameters);

        return newRowsResponse(
          columnNames: null,
          tableNames: null,
          typeVector: null,
          rows: null,
          autoCommit: db.autocommit,
          lastInsertRowId: db.lastInsertRowId,
          requestId: request.requestId,
        );
      }
    });
  }

  @override
  Future<Response> handleExclusiveLock(
    RequestExclusiveLock request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    final lock = await database.obtainLockAsync(abortSignal);
    return newSimpleSuccessResponse(
      response: lock.toJS,
      requestId: request.requestId,
    );
  }

  @override
  Response handleReleaseLock(ReleaseLock request, AbortSignal abortSignal) {
    final database = _requireDatabase(request);
    database.releaseLock(request.lockId);
    return newSimpleSuccessResponse(
      response: null,
      requestId: request.requestId,
    );
  }

  @override
  FutureOr<Response> handleCommitRequest(
    CommitsStreamRequest request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    if (request.action) {
      return await subscribe(database.commits, () async {
        final rawDatabase = await database.database.opened;
        return rawDatabase.database.commits.listen((event) {
          sendNotification(newCommitNotification(databaseId: database.id));
        });
      }, request);
    } else {
      database.commits.cancel();

      return newSimpleSuccessResponse(
        response: null,
        requestId: request.requestId,
      );
    }
  }

  @override
  FutureOr<Response> handleRollbackRequest(
    RollbackStreamRequest request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    if (request.action) {
      return await subscribe(database.rollbacks, () async {
        final rawDatabase = await database.database.opened;
        return rawDatabase.database.rollbacks.listen((event) {
          sendNotification(newRollbackNotification(databaseId: database.id));
        });
      }, request);
    } else {
      database.rollbacks.cancel();

      return newSimpleSuccessResponse(
        response: null,
        requestId: request.requestId,
      );
    }
  }

  @override
  FutureOr<Response> handleUpdateRequest(
    UpdateStreamRequest request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    if (request.action) {
      return await subscribe(database.updates, () async {
        final rawDatabase = await database.database.opened;
        return rawDatabase.database.updates.listen((event) {
          sendNotification(
            newUpdateNotification(
              updateKind: event.kind.index,
              rowId: event.rowId,
              updateTableName: event.tableName,
              databaseId: database.id,
            ),
          );
        });
      }, request);
    } else {
      database.updates.cancel();

      return newSimpleSuccessResponse(
        response: null,
        requestId: request.requestId,
      );
    }
  }

  @override
  Future<Response> handleOpenAdditionalConnection(
    OpenAdditionalConnection request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request).database;
    database.refCount++;
    final (endpoint, channel) = await createChannel();

    final client = _runner._accept(channel);
    client._openedDatabases.add(_ConnectionDatabase(database, 0));

    return newEndpointResponse(
      requestId: request.requestId,
      endpoint: endpoint,
    );
  }

  @override
  Future<Response> handleCloseDatabase(
    CloseDatabase request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    _openedDatabases.remove(database);
    await database.close();
    return newSimpleSuccessResponse(
      response: null,
      requestId: request.requestId,
    );
  }

  @override
  Future<Response> handleFileSystemFlush(
    FileSystemFlushRequest request,
    AbortSignal abortSignal,
  ) async {
    if (await _requireDatabase(request).database.vfs
        case IndexedDbFileSystem idb) {
      await idb.flush();
    }

    return newSimpleSuccessResponse(
      response: null,
      requestId: request.requestId,
    );
  }

  @override
  Future<Response> handleFileSystemAccess(
    FileSystemAccess request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    final fsType = FileType.values[request.fsType];
    final buffer = request.buffer;

    final vfs = await database.database.vfs;
    final file = vfs
        .xOpen(Sqlite3Filename(fsType.pathInVfs), SqlFlag.SQLITE_OPEN_CREATE)
        .file;

    try {
      if (buffer != null) {
        final asDartBuffer = buffer.toDart;
        file.xTruncate(asDartBuffer.lengthInBytes);
        file.xWrite(asDartBuffer.asUint8List(), 0);

        return newSimpleSuccessResponse(
          response: null,
          requestId: request.requestId,
        );
      } else {
        final buffer = Uint8List(file.xFileSize());
        file.xRead(buffer, 0);

        return newSimpleSuccessResponse(
          response: buffer.buffer.toJS,
          requestId: request.requestId,
        );
      }
    } finally {
      file.xClose();
    }
  }

  @override
  FutureOr<Response> handleFileSystemExists(
    FileSystemExistsQuery request,
    AbortSignal abortSignal,
  ) async {
    final database = _requireDatabase(request);
    final vfs = await database.database.vfs;
    final exists =
        vfs.xAccess(FileType.values[request.fsType].pathInVfs, 0) == 1;

    return newSimpleSuccessResponse(
      response: exists.toJS,
      requestId: request.requestId,
    );
  }

  Future<Response> subscribe(
    _StreamState state,
    Future<StreamSubscription<void>> Function() subscribeInternally,
    StreamRequest request,
  ) async {
    state.subscription ??= await subscribeInternally();
    return newSimpleSuccessResponse(
      response: null,
      requestId: request.requestId,
    );
  }

  @override
  void handleNotification(Notification notification) {
    // There aren't supposed to be any notifications from the client.
  }

  @override
  Future<JSAny?> customRequest(JSAny? request) async {
    final response = await sendRequest(
      newCustomRequest(requestId: 0, payload: request, databaseId: null),
      MessageType.simpleSuccessResponse,
    );
    return response.response;
  }

  _ConnectionDatabase _databaseById(int id) {
    return _openedDatabases.firstWhere((e) => e.id == id);
  }

  _ConnectionDatabase _requireDatabase(Request request) {
    if (request.databaseId case final id?) {
      return _databaseById(id);
    } else {
      throw ArgumentError('Request requires database id');
    }
  }
}

extension on FileType {
  String get pathInVfs => switch (this) {
    FileType.database => '/database',
    FileType.journal => '/database-journal',
  };
}

final class DatabaseState {
  final WorkerRunner runner;
  final int id;
  final String name;
  final FileSystemImplementation mode;
  final JSAny? additionalOptions;
  final DatabaseLocks locks;
  int refCount = 1;

  Future<WorkerDatabase>? _database;
  Future<void>? _openVfs;
  VirtualFileSystem? _resolvedVfs;

  /// Runs additional async work, such as flushing the VFS to IndexedDB when
  /// the database is closed.
  FutureOr<void> Function()? closeHandler;

  DatabaseState({
    required this.id,
    required this.runner,
    required this.name,
    required this.mode,
    required this.additionalOptions,
  }) : locks = DatabaseLocks('pkg-sqlite3-web-$name', mode.needsExternalLocks);

  String get vfsName => 'vfs-web-$id';

  Future<VirtualFileSystem> get vfs async {
    await (_openVfs ??= Future.sync(() async {
      switch (mode) {
        case FileSystemImplementation.opfsAtomics:
          final options = WasmVfs.createOptions(root: pathForOpfs(name));
          final worker = runner._environment.connector.spawnDedicatedWorker()!;

          newStartFileSystemServer(options: options).sendToWorker(worker);

          // Wait for the server worker to report that it's ready
          await EventStreamProviders.messageEvent
              .forTarget(worker.targetForErrorEvents)
              .first;

          final wasmVfs = _resolvedVfs = WasmVfs(
            workerOptions: options,
            vfsName: vfsName,
          );
          closeHandler = wasmVfs.close;
        case FileSystemImplementation.opfsShared:
          final simple = _resolvedVfs =
              await SimpleOpfsFileSystem.loadFromStorage(
                pathForOpfs(name),
                vfsName: vfsName,
              );
          closeHandler = simple.close;
        case FileSystemImplementation.opfsExternalLocks:
          final simple = _resolvedVfs =
              await SimpleOpfsFileSystem.loadFromStorage(
                pathForOpfs(name),
                vfsName: vfsName,
                readWriteUnsafe: true,
              );
          closeHandler = simple.close;
        case FileSystemImplementation.indexedDb:
          final idb = _resolvedVfs = await IndexedDbFileSystem.open(
            dbName: name,
            vfsName: vfsName,
          );
          closeHandler = idb.close;
        case FileSystemImplementation.inMemory:
          _resolvedVfs = InMemoryFileSystem(name: vfsName);
      }
    }));

    return _resolvedVfs!;
  }

  Future<WorkerDatabase> get opened async {
    final database = _database ??= Future.sync(() async {
      final sqlite3 = await runner._sqlite3!;
      final fileSystem = await vfs;

      sqlite3.registerVirtualFileSystem(fileSystem);
      return await locks.lock(() {
        return runner._controller.openDatabase(
          sqlite3,
          // We're currently using /database as the in-VFS path. This is because
          // we need to pre-open persistent files in SimpleOpfsFileSystem, and
          // that VFS only stores `/database` and `/database-journal`.
          // We still provide support for multiple databases by keeping multiple
          // VFS instances around.
          '/database',
          vfsName,
          additionalOptions,
        );
      }, null);
    });

    return await database;
  }

  Future<void> decrementRefCount() async {
    if (--refCount == 0) {
      await close();
    }
  }

  Future<void> close() async {
    final sqlite3 = await runner._sqlite3!;
    final database = await _database!;

    database.database.close();
    if (_resolvedVfs case final vfs?) {
      sqlite3.unregisterVirtualFileSystem(vfs);
    }

    await closeHandler?.call();
  }
}

final class WorkerRunner {
  final WorkerEnvironment _environment;
  final DatabaseController _controller;

  final List<_ClientConnection> _connections = [];
  var _nextConnectionId = 0;

  final Map<int, DatabaseState> openedDatabases = {};
  var _nextDatabaseId = 0;

  Future<WasmSqlite3>? _sqlite3;
  Uri? _wasmUri;

  final Mutex _compatibilityCheck = Mutex();
  CompatibilityResult? _compatibilityResult;

  /// For shared workers, a dedicated inner worker allowing tabs to connect to
  /// a shared context that can use synchronous JS APIs.
  late final WorkerHandle? _innerWorker = _environment.connector
      .spawnDedicatedWorker();

  WorkerRunner(this._controller, this._environment);

  void handleRequests() async {
    await for (final message in _environment.topLevelRequests) {
      if (message.type == MessageType.connect.name) {
        final channel = (message as ConnectRequest).endpoint.connect();
        _accept(channel);
      } else if (message.type == MessageType.startFileSystemServer.name) {
        final worker = await VfsWorker.create(
          (message as StartFileSystemServer).options,
        );
        // Inform the requester that the VFS is ready
        (globalContext as DedicatedWorkerGlobalScope).postMessage(true.toJS);
        await worker.start();
      } else if (isCompatibilityCheck(message.type)) {
        // A compatibility check message is sent to dedicated workers inside of
        // shared workers, we respond through the top-level port.
        final result = await checkCompatibility(message as CompatibilityCheck);
        (globalContext as DedicatedWorkerGlobalScope).postMessage(result.toJS);
      }
    }
  }

  _ClientConnection _accept(StreamChannel<Message> channel) {
    final connection = _ClientConnection(
      runner: this,
      channel: channel,
      id: _nextConnectionId++,
    );
    _connections.add(connection);
    connection.closed.whenComplete(() => _connections.remove(connection));

    return connection;
  }

  Future<CompatibilityResult> checkCompatibility(CompatibilityCheck check) {
    return _compatibilityCheck.withCriticalSection(() async {
      if (_compatibilityResult != null) {
        // todo: We may have to update information about existing databases
        // as they come and go
        return _compatibilityResult!;
      }

      var supportsOpfs = false;
      var opfsSupportsReadWriteUnsafe = false;
      final databaseName = check.databaseName;
      if (check.shouldCheckOpfsCompatibility) {
        (
          basicSupport: supportsOpfs,
          supportsReadWriteUnsafe: opfsSupportsReadWriteUnsafe,
        ) = await checkOpfsSupport();
      }

      final supportsIndexedDb = check.shouldCheckIndexedDbCompatbility
          ? await checkIndexedDbSupport()
          : false;

      var sharedCanSpawnDedicated = false;
      final existingDatabases = <ExistingDatabase>{};

      if (check.type == MessageType.sharedCompatibilityCheck.name) {
        if (_innerWorker case final innerWorker?) {
          sharedCanSpawnDedicated = true;

          newDedicatedInSharedCompatibilityCheck(
            databaseName: databaseName,
            requestId: 0,
          ).sendToWorker(innerWorker);

          final response = await EventStreamProviders.messageEvent
              .forTarget(innerWorker.targetForErrorEvents)
              .first;
          final result = CompatibilityResult.fromJS(response.data as JSObject);

          supportsOpfs = result.canUseOpfs;
          opfsSupportsReadWriteUnsafe = result.opfsSupportsReadWriteUnsafe;
          existingDatabases.addAll(result.existingDatabases);
        }
      }

      if (supportsOpfs) {
        for (final database in await opfsDatabases()) {
          existingDatabases.add((StorageMode.opfs, database));
        }
      }
      if (supportsIndexedDb && databaseName != null) {
        if (await checkIndexedDbExists(databaseName)) {
          existingDatabases.add((StorageMode.indexedDb, databaseName));
        }
      }

      return CompatibilityResult(
        existingDatabases: existingDatabases.toList(),
        sharedCanSpawnDedicated: sharedCanSpawnDedicated,
        canUseOpfs: supportsOpfs,
        opfsSupportsReadWriteUnsafe: opfsSupportsReadWriteUnsafe,
        canUseIndexedDb: supportsIndexedDb,
        supportsSharedArrayBuffers: globalContext.has('SharedArrayBuffer'),
        dedicatedWorkersCanNest: globalContext.has('Worker'),
      );
    });
  }

  Future<void> loadWasmModule(Uri uri) async {
    if (_sqlite3 != null) {
      if (_wasmUri != uri) {
        throw StateError(
          'Workers only support a single sqlite3 wasm module, provided '
          'different URI (has $_wasmUri, got $uri)',
        );
      }

      await _sqlite3;
    } else {
      final future = _sqlite3 = _controller.loadWasmModule(uri).onError((
        error,
        stackTrace,
      ) {
        _sqlite3 = null;
        throw error!;
      });
      await future;
      _wasmUri = uri;
    }
  }

  DatabaseState findDatabase(
    String name,
    FileSystemImplementation mode,
    JSAny? additionalOptions,
  ) {
    for (final existing in openedDatabases.values) {
      if (existing.refCount != 0 &&
          existing.name == name &&
          existing.mode == mode) {
        existing.refCount++;
        return existing;
      }
    }

    final id = _nextDatabaseId++;
    return openedDatabases[id] = DatabaseState(
      id: id,
      runner: this,
      name: name,
      mode: mode,
      additionalOptions: additionalOptions,
    );
  }
}

typedef OpfsSupport = ({bool basicSupport, bool supportsReadWriteUnsafe});

/// Checks whether the OPFS API is likely to be correctly implemented in the
/// current browser.
///
/// Since OPFS uses the synchronous file system access API, this method can only
/// return true when called in a dedicated worker.
Future<OpfsSupport> checkOpfsSupport() async {
  const noSupport = (basicSupport: false, supportsReadWriteUnsafe: false);
  final storage = storageManager;

  if (storage == null) return noSupport;

  const testFileName = '_drift_feature_detection';

  FileSystemDirectoryHandle? opfsRoot;
  FileSystemFileHandle? fileHandle;
  JSObject? openedFile;
  var canOpenWithReadWriteUnsafe = false;

  try {
    opfsRoot = await storage.directory;

    fileHandle = await opfsRoot.openFile(testFileName, create: true);
    (canOpenWithReadWriteUnsafe, openedFile) =
        await _tryOpeningWithReadWriteUnsafe(fileHandle);

    // In earlier versions of the OPFS standard, some methods like `getSize()`
    // on a sync file handle have actually been asynchronous. We don't support
    // Browsers that implement the outdated spec.
    final getSizeResult = openedFile.callMethod('getSize'.toJS);
    if (getSizeResult.typeofEquals('object')) {
      // Returned a promise, that's no good.
      await (getSizeResult as JSPromise).toDart;
      return noSupport;
    }

    return (
      basicSupport: true,
      supportsReadWriteUnsafe: canOpenWithReadWriteUnsafe,
    );
  } on Object {
    return noSupport;
  } finally {
    if (openedFile != null) {
      (openedFile as FileSystemSyncAccessHandle).close();
    }

    if (opfsRoot != null && fileHandle != null) {
      await opfsRoot.remove(testFileName);
    }
  }
}

Future<(bool, FileSystemSyncAccessHandle)> _tryOpeningWithReadWriteUnsafe(
  FileSystemFileHandle handle,
) async {
  FileSystemSyncAccessHandle? opened;

  try {
    // First, try opening with readwrite-unsafe
    opened = await ProposedLockingSchemeApi(handle)
        .createSyncAccessHandle(
          FileSystemCreateSyncAccessHandleOptions.unsafeReadWrite(),
        )
        .toDart;

    // The mode is supported if we can do it again (that means no lock has been
    // applied).
    final openedAgain = await ProposedLockingSchemeApi(handle)
        .createSyncAccessHandle(
          FileSystemCreateSyncAccessHandleOptions.unsafeReadWrite(),
        )
        .toDart;
    openedAgain.close();

    return (true, opened);
  } catch (e) {
    opened?.close();

    // Fallback to opening without the special option.
    final sync = await handle.createSyncAccessHandle().toDart;
    return (false, sync);
  }
}
