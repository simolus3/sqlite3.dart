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
        MessageEvent,
        MessagePort,
        SharedWorkerGlobalScope,
        Worker,
        AbortController;
// ignore: implementation_imports
import 'package:sqlite3/src/wasm/js_interop/new_file_system_access.dart';

import 'database.dart';
import 'channel.dart';
import 'locks.dart';
import 'protocol.dart';
import 'shared.dart';
import 'types.dart';

sealed class WorkerEnvironment {
  WorkerEnvironment._();

  factory WorkerEnvironment() {
    final context = globalContext;
    if (context.instanceOfString('DedicatedWorkerGlobalScope')) {
      return Dedicated();
    } else {
      return Shared();
    }
  }

  /// Messages outside of a connection being posted to the worker or a connect
  /// port of a shared worker.
  ///
  /// We're not using them for actual channels, but instead have clients
  /// setup message ports which are then forwarded to workers using these
  /// top-level requests.
  Stream<Message> get topLevelRequests;
}

final class Dedicated extends WorkerEnvironment {
  final DedicatedWorkerGlobalScope scope;

  Dedicated()
      : scope = globalContext as DedicatedWorkerGlobalScope,
        super._();

  @override
  Stream<Message> get topLevelRequests {
    return EventStreamProviders.messageEvent.forTarget(scope).map((event) {
      return Message.deserialize(event.data as JSObject);
    });
  }
}

final class Shared extends WorkerEnvironment {
  final SharedWorkerGlobalScope scope;

  Shared()
      : scope = globalContext as SharedWorkerGlobalScope,
        super._();

  @override
  Stream<Message> get topLevelRequests {
    // Listen for connect events, then watch each connected port to send a a
    // connect message.
    // Tabs will only use one message port to this worker, but may use multiple
    // connections for different databases. So we're not using the connect port
    // for the actual connection and instead wait for clients to send message
    // ports through the connect port.
    return Stream.multi((listener) {
      final connectPorts = <MessagePort>[];
      final subscriptions = <StreamSubscription>[];

      void handlePort(MessagePort port) {
        connectPorts.add(port);
        port.start();

        subscriptions.add(
            EventStreamProviders.messageEvent.forTarget(port).listen((event) {
          listener.addSync(Message.deserialize(event.data as JSObject));
        }));
      }

      subscriptions.add(
          EventStreamProviders.connectEvent.forTarget(scope).listen((event) {
        for (final port in (event as MessageEvent).ports.toDart) {
          handlePort(port);
        }
      }));

      listener.onCancel = () {
        for (final subscription in subscriptions) {
          subscription.cancel();
        }
      };
    });
  }
}

/// A fake worker environment running in the same context as the main
/// application.
///
/// This allows using a communication channel based on message ports regardless
/// of where the database is hosted. While that adds overhead, a local
/// environment is only used as a fallback if workers are unavailable.
final class Local extends WorkerEnvironment {
  final StreamController<Message> _messages = StreamController();

  Local() : super._();

  void addTopLevelMessage(Message message) {
    _messages.add(message);
  }

  void close() {
    _messages.close();
  }

  @override
  Stream<Message> get topLevelRequests {
    return _messages.stream;
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
      int? lockId, AbortSignal abortSignal, T Function() block) {
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

    database.locks.lock(() {
      // Since we just obtained an exclusive lock, we cannot possibly be holding
      // the lock already.
      assert(_heldLock == null);

      final id = _nextLockId++;
      final completer = Completer<void>();
      _heldLock = (id, completer);
      resolvedLockId.complete(id);
      return completer.future;
    }, started.signal).onError<Object>((e, s) {
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

  _ClientConnection(
      {required WorkerRunner runner,
      required StreamChannel<Message> channel,
      required this.id})
      : _runner = runner,
        super(channel) {
    closed.whenComplete(() async {
      for (final id in _openedDatabases) {
        await id.close();
      }
      _openedDatabases.clear();
    });
  }

  @override
  Future<Response> handleCompatibilityCheck(
      CompatibilityCheck request, AbortSignal abortSignal) async {
    return SimpleSuccessResponse(
      response: (await _runner.checkCompatibility(request)).toJS,
      requestId: request.requestId,
    );
  }

  @override
  Future<Response> handleConnect(
      ConnectRequest request, AbortSignal abortSignal) async {
    final inner = _runner.useOrSpawnInnerWorker();
    ConnectRequest(endpoint: request.endpoint, requestId: 0)
        .sendToWorker(inner);

    return SimpleSuccessResponse(response: null, requestId: request.requestId);
  }

  @override
  Future<Response> handleCustom(
      CustomRequest request, AbortSignal abortSignal) async {
    JSAny? response;

    if (request.databaseId case final id?) {
      response = await (await _databaseById(id).database.opened)
          .handleCustomRequest(this, request.payload);
    } else {
      response =
          await _runner._controller.handleCustomRequest(this, request.payload);
    }

    return SimpleSuccessResponse(
        requestId: request.requestId, response: response);
  }

  @override
  Future<Response> handleOpen(
      OpenRequest request, AbortSignal abortSignal) async {
    await _runner.loadWasmModule(request.wasmUri);
    DatabaseState? database;
    _ConnectionDatabase? connectionDatabase;

    try {
      database = _runner.findDatabase(
          request.databaseName, request.storageMode, request.additionalData);

      await (request.onlyOpenVfs ? database.vfs : database.opened);

      connectionDatabase = _ConnectionDatabase(database);
      _openedDatabases.add(connectionDatabase);

      return SimpleSuccessResponse(
          response: database.id.toJS, requestId: request.requestId);
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
      RunQuery request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request);
    final openedDatabase = await database.database.opened;

    return database.useLock(request.lockId, abortSignal, () {
      final db = openedDatabase.database;

      if (request.checkInTransaction && db.autocommit) {
        throw StateError('Database is not in a transaction');
      }

      ResultSet? resultSet;
      if (request.returnRows) {
        resultSet = db.select(request.sql, request.parameters);
      } else {
        db.execute(request.sql, request.parameters);
      }

      return RowsResponse(
        resultSet: resultSet,
        requestId: request.requestId,
        autocommit: db.autocommit,
        lastInsertRowId: db.lastInsertRowId,
      );
    });
  }

  @override
  Future<Response> handleExclusiveLock(
      RequestExclusiveLock request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request);
    final lock = await database.obtainLockAsync(abortSignal);
    return SimpleSuccessResponse(
        response: lock.toJS, requestId: request.requestId);
  }

  @override
  Response handleReleaseLock(ReleaseLock request, AbortSignal abortSignal) {
    final database = _requireDatabase(request);
    database.releaseLock(request.lockId);
    return SimpleSuccessResponse(response: null, requestId: request.requestId);
  }

  @override
  Future<Response> handleStream(
      StreamRequest request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request);

    if (request.action) {
      // Subscribe.
      switch (request.type) {
        case MessageType.updateRequest:
          return await subscribe(database.updates, () async {
            final rawDatabase = await database.database.opened;
            return rawDatabase.database.updates.listen((event) {
              sendNotification(
                  UpdateNotification(update: event, databaseId: database.id));
            });
          }, request);
        case MessageType.commitRequest:
          return await subscribe(database.commits, () async {
            final rawDatabase = await database.database.opened;
            return rawDatabase.database.commits.listen((event) {
              sendNotification(EmptyNotification(
                  type: MessageType.notifyCommit, databaseId: database.id));
            });
          }, request);
        case MessageType.rollbackRequest:
          return await subscribe(database.rollbacks, () async {
            final rawDatabase = await database.database.opened;
            return rawDatabase.database.rollbacks.listen((event) {
              sendNotification(EmptyNotification(
                  type: MessageType.notifyRollback, databaseId: database.id));
            });
          }, request);
        default:
          throw ArgumentError('Unknown stream to subscribe to');
      }
    } else {
      // Unsubscribe.
      final handler = switch (request.type) {
        MessageType.updateRequest => database.updates,
        MessageType.rollbackRequest => database.rollbacks,
        MessageType.commitRequest => database.commits,
        _ => throw ArgumentError('Unknown stream to unsubscribe from'),
      };
      handler.cancel();

      return SimpleSuccessResponse(
          response: null, requestId: request.requestId);
    }
  }

  @override
  Future<Response> handleOpenAdditionalConnection(
      OpenAdditonalConnection request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request).database;
    database.refCount++;
    final (endpoint, channel) = await createChannel();

    final client = _runner._accept(channel);
    client._openedDatabases.add(_ConnectionDatabase(database, 0));

    return EndpointResponse(requestId: request.requestId, endpoint: endpoint);
  }

  @override
  Future<Response> handleCloseDatabase(
      CloseDatabase request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request);
    _openedDatabases.remove(database);
    await database.close();
    return SimpleSuccessResponse(response: null, requestId: request.requestId);
  }

  @override
  Future<Response> handleFileSystemFlush(
      FileSystemFlushRequest request, AbortSignal abortSignal) async {
    if (await _requireDatabase(request).database.vfs
        case IndexedDbFileSystem idb) {
      await idb.flush();
    }

    return SimpleSuccessResponse(response: null, requestId: request.requestId);
  }

  @override
  Future<Response> handleFileSystemAccess(
      FileSystemAccess request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request);
    final fsType = request.fsType;
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

        return SimpleSuccessResponse(
            response: null, requestId: request.requestId);
      } else {
        final buffer = Uint8List(file.xFileSize());
        file.xRead(buffer, 0);

        return SimpleSuccessResponse(
            response: buffer.buffer.toJS, requestId: request.requestId);
      }
    } finally {
      file.xClose();
    }
  }

  @override
  FutureOr<Response> handleFileSystemExists(
      FileSystemExistsQuery request, AbortSignal abortSignal) async {
    final database = _requireDatabase(request);
    final vfs = await database.database.vfs;
    final exists = vfs.xAccess(request.fsType.pathInVfs, 0) == 1;

    return SimpleSuccessResponse(
        response: exists.toJS, requestId: request.requestId);
  }

  Future<Response> subscribe(
    _StreamState state,
    Future<StreamSubscription<void>> Function() subscribeInternally,
    StreamRequest request,
  ) async {
    state.subscription ??= await subscribeInternally();
    return SimpleSuccessResponse(response: null, requestId: request.requestId);
  }

  @override
  void handleNotification(Notification notification) {
    // There aren't supposed to be any notifications from the client.
  }

  @override
  Future<JSAny?> customRequest(JSAny? request) async {
    final response = await sendRequest(
        CustomRequest(requestId: 0, payload: request),
        MessageType.simpleSuccessResponse);
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
          final worker = Worker(Uri.base.toString().toJS);

          StartFileSystemServer(options: options).sendToWorker(worker);

          // Wait for the server worker to report that it's ready
          await EventStreamProviders.messageEvent.forTarget(worker).first;

          final wasmVfs =
              _resolvedVfs = WasmVfs(workerOptions: options, vfsName: vfsName);
          closeHandler = wasmVfs.close;
        case FileSystemImplementation.opfsShared:
          final simple = _resolvedVfs =
              await SimpleOpfsFileSystem.loadFromStorage(pathForOpfs(name),
                  vfsName: vfsName);
          closeHandler = simple.close;
        case FileSystemImplementation.opfsExternalLocks:
          final simple = _resolvedVfs =
              await SimpleOpfsFileSystem.loadFromStorage(pathForOpfs(name),
                  vfsName: vfsName, readWriteUnsafe: true);
          closeHandler = simple.close;
        case FileSystemImplementation.indexedDb:
          final idb = _resolvedVfs =
              await IndexedDbFileSystem.open(dbName: name, vfsName: vfsName);
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
          vfsName, additionalOptions,
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

    database.database.dispose();
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
  Worker? _innerWorker;

  WorkerRunner(this._controller, {WorkerEnvironment? environment})
      : _environment = environment ?? WorkerEnvironment();

  void handleRequests() async {
    await for (final message in _environment.topLevelRequests) {
      if (message is ConnectRequest) {
        final channel = message.endpoint.connect();
        _accept(channel);
      } else if (message is StartFileSystemServer) {
        final worker = await VfsWorker.create(message.options);
        // Inform the requester that the VFS is ready
        (_environment as Dedicated).scope.postMessage(true.toJS);
        await worker.start();
      } else if (message is CompatibilityCheck) {
        // A compatibility check message is sent to dedicated workers inside of
        // shared workers, we respond through the top-level port.
        final result = await checkCompatibility(message);
        (_environment as Dedicated).scope.postMessage(result.toJS);
      }
    }
  }

  _ClientConnection _accept(StreamChannel<Message> channel) {
    final connection = _ClientConnection(
        runner: this, channel: channel, id: _nextConnectionId++);
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
          supportsReadWriteUnsafe: opfsSupportsReadWriteUnsafe
        ) = await checkOpfsSupport();
      }

      final supportsIndexedDb = check.shouldCheckIndexedDbCompatbility
          ? await checkIndexedDbSupport()
          : false;

      var sharedCanSpawnDedicated = false;
      final existingDatabases = <ExistingDatabase>{};

      if (check.type == MessageType.sharedCompatibilityCheck) {
        if (globalContext.has('Worker')) {
          sharedCanSpawnDedicated = true;

          final worker = useOrSpawnInnerWorker();
          CompatibilityCheck(
            databaseName: databaseName,
            type: MessageType.dedicatedInSharedCompatibilityCheck,
            requestId: 0,
          ).sendToWorker(worker);

          final response =
              await EventStreamProviders.messageEvent.forTarget(worker).first;
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
            'different URI (has $_wasmUri, got $uri)');
      }

      await _sqlite3;
    } else {
      final future = _sqlite3 =
          _controller.loadWasmModule(uri).onError((error, stackTrace) {
        _sqlite3 = null;
        throw error!;
      });
      await future;
      _wasmUri = uri;
    }
  }

  DatabaseState findDatabase(
      String name, FileSystemImplementation mode, JSAny? additionalOptions) {
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

  Worker useOrSpawnInnerWorker() {
    return _innerWorker ??= Worker(Uri.base.toString().toJS);
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
      supportsReadWriteUnsafe: canOpenWithReadWriteUnsafe
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
    FileSystemFileHandle handle) async {
  FileSystemSyncAccessHandle? opened;

  try {
    // First, try opening with readwrite-unsafe
    opened = await ProposedLockingSchemeApi(handle)
        .createSyncAccessHandle(
            FileSystemCreateSyncAccessHandleOptions.unsafeReadWrite())
        .toDart;

    // The mode is supported if we can do it again (that means no lock has been
    // applied).
    final openedAgain = await ProposedLockingSchemeApi(handle)
        .createSyncAccessHandle(
            FileSystemCreateSyncAccessHandleOptions.unsafeReadWrite())
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
