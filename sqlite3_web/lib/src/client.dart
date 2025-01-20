import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:sqlite3/wasm.dart' hide WorkerOptions;
import 'package:web/web.dart'
    hide Response, Request, FileSystem, Notification, Lock;

import 'types.dart';
import 'channel.dart';
import 'database.dart';
import 'protocol.dart';
import 'shared.dart';
import 'worker.dart';

final class _CommitOrRollbackStream {
  StreamSubscription<Notification>? workerSubscription;
  final StreamController<void> controller = StreamController.broadcast();
}

final class RemoteDatabase implements Database {
  final WorkerConnection connection;
  final int databaseId;

  var _isClosed = false;

  StreamSubscription<Notification>? _updateNotificationSubscription;
  final StreamController<SqliteUpdate> _updates = StreamController.broadcast();

  final _CommitOrRollbackStream _commits = _CommitOrRollbackStream();
  final _CommitOrRollbackStream _rollbacks = _CommitOrRollbackStream();

  RemoteDatabase({required this.connection, required this.databaseId}) {
    _updates
      ..onListen = (() {
        _updateNotificationSubscription ??=
            connection.notifications.stream.listen((notification) {
          if (notification case UpdateNotification()) {
            if (notification.databaseId == databaseId) {
              _updates.add(notification.update);
            }
          }
        });
        _requestStreamUpdates(MessageType.updateRequest, true);
      })
      ..onCancel = (() {
        _updateNotificationSubscription?.cancel();
        _updateNotificationSubscription = null;
        _requestStreamUpdates(MessageType.updateRequest, false);
      });

    _setupCommitOrRollbackStream(
        _commits, MessageType.commitRequest, MessageType.notifyCommit);
    _setupCommitOrRollbackStream(
        _rollbacks, MessageType.rollbackRequest, MessageType.notifyRollback);
  }

  void _setupCommitOrRollbackStream(
    _CommitOrRollbackStream stream,
    MessageType requestSubscription,
    MessageType notificationType,
  ) {
    stream.controller
      ..onListen = (() {
        stream.workerSubscription ??=
            connection.notifications.stream.listen((notification) {
          if (notification case EmptyNotification(type: final type)) {
            if (notification.databaseId == databaseId &&
                type == notificationType) {
              stream.controller.add(null);
            }
          }
        });
        _requestStreamUpdates(requestSubscription, true);
      })
      ..onCancel = (() {
        stream.workerSubscription?.cancel();
        stream.workerSubscription = null;
        _requestStreamUpdates(requestSubscription, false);
      });
  }

  void _requestStreamUpdates(MessageType streamType, bool subscribe) {
    if (!_isClosed) {
      connection.sendRequest(
        StreamRequest(
          type: streamType,
          action: subscribe,
          requestId: 0, // filled out in sendRequest
          databaseId: databaseId,
        ),
        MessageType.simpleSuccessResponse,
      );
    }
  }

  @override
  Future<void> get closed {
    return connection.closed;
  }

  @override
  Future<void> dispose() async {
    _isClosed = true;
    await (
      _updates.close(),
      _rollbacks.controller.close(),
      _commits.controller.close(),
      connection.sendRequest(
          CloseDatabase(requestId: 0, databaseId: databaseId),
          MessageType.simpleSuccessResponse)
    ).wait;
  }

  @override
  Future<JSAny?> customRequest(JSAny? request) async {
    final response = await connection.sendRequest(
      CustomRequest(requestId: 0, payload: request, databaseId: databaseId),
      MessageType.simpleSuccessResponse,
    );
    return response.response;
  }

  @override
  Future<void> execute(String sql,
      [List<Object?> parameters = const []]) async {
    await connection.sendRequest(
      RunQuery(
        requestId: 0,
        databaseId: databaseId,
        sql: sql,
        parameters: parameters,
        returnRows: false,
      ),
      MessageType.simpleSuccessResponse,
    );
  }

  @override
  late final FileSystem fileSystem = RemoteFileSystem(this);

  @override
  Future<int> get lastInsertRowId async {
    final result = await select('select last_insert_rowid();');
    return result.single.columnAt(0) as int;
  }

  @override
  Future<ResultSet> select(String sql,
      [List<Object?> parameters = const []]) async {
    final response = await connection.sendRequest(
      RunQuery(
        requestId: 0,
        databaseId: databaseId,
        sql: sql,
        parameters: parameters,
        returnRows: true,
      ),
      MessageType.rowsResponse,
    );

    return response.resultSet;
  }

  @override
  Future<void> setUserVersion(int version) async {
    await execute('pragma user_version = ?', [version]);
  }

  @override
  Stream<SqliteUpdate> get updates => _updates.stream;

  @override
  Stream<void> get rollbacks => _rollbacks.controller.stream;

  @override
  Stream<void> get commits => _commits.controller.stream;

  @override
  Future<int> get userVersion async {
    final result = await select('pragma user_version;');
    return result.single.columnAt(0) as int;
  }

  @override
  Future<SqliteWebEndpoint> additionalConnection() async {
    final response = await connection.sendRequest(
      OpenAdditonalConnection(requestId: 0, databaseId: databaseId),
      MessageType.endpointResponse,
    );
    final endpoint = response.endpoint;
    return (endpoint.port, endpoint.lockName!);
  }
}

final class RemoteFileSystem implements FileSystem {
  final RemoteDatabase database;

  RemoteFileSystem(this.database);

  @override
  Future<bool> exists(FileType type) async {
    final response = await database.connection.sendRequest(
      FileSystemExistsQuery(
        databaseId: database.databaseId,
        fsType: type,
        requestId: 0,
      ),
      MessageType.simpleSuccessResponse,
    );

    return (response.response as JSBoolean).toDart;
  }

  @override
  Future<void> flush() async {
    await database.connection.sendRequest(
      FileSystemFlushRequest(databaseId: database.databaseId, requestId: 0),
      MessageType.simpleSuccessResponse,
    );
  }

  @override
  Future<Uint8List> readFile(FileType type) async {
    final response = await database.connection.sendRequest(
      FileSystemAccess(
        databaseId: database.databaseId,
        requestId: 0,
        buffer: null,
        fsType: type,
      ),
      MessageType.simpleSuccessResponse,
    );

    final buffer = (response.response as JSArrayBuffer);
    return buffer.toDart.asUint8List();
  }

  @override
  Future<void> writeFile(FileType type, Uint8List content) async {
    // We need to copy since we're about to transfer contents over
    final copy = Uint8List(content.length)..setAll(0, content);

    await database.connection.sendRequest(
      FileSystemAccess(
        databaseId: database.databaseId,
        requestId: 0,
        buffer: copy.buffer.toJS,
        fsType: type,
      ),
      MessageType.simpleSuccessResponse,
    );
  }
}

final class WorkerConnection extends ProtocolChannel {
  final StreamController<Notification> notifications =
      StreamController.broadcast();

  WorkerConnection(super.channel) {
    closed.whenComplete(notifications.close);
  }

  @override
  Future<Response> handleRequest(Request request) {
    // TODO: implement handleRequest
    throw UnimplementedError();
  }

  @override
  void handleNotification(Notification notification) {
    notifications.add(notification);
  }
}

final class DatabaseClient implements WebSqlite {
  final Uri workerUri;
  final Uri wasmUri;
  final DatabaseController _localController;

  final Lock _startWorkersLock = Lock();
  bool _startedWorkers = false;
  WorkerConnection? _connectionToDedicated;
  WorkerConnection? _connectionToShared;
  WorkerConnection? _connectionToDedicatedInShared;

  WorkerConnection? _connectionToLocal;

  final Set<MissingBrowserFeature> _missingFeatures = {};

  DatabaseClient(this.workerUri, this.wasmUri, this._localController);

  Future<void> startWorkers() {
    return _startWorkersLock.synchronized(() async {
      if (_startedWorkers) {
        return;
      }
      _startedWorkers = true;

      await _startDedicated();
      await _startShared();
    });
  }

  Future<void> _startDedicated() async {
    if (globalContext.has('Worker')) {
      final Worker dedicated;
      try {
        dedicated = Worker(
          workerUri.toString().toJS,
          WorkerOptions(name: 'sqlite3_worker'),
        );
      } on Object {
        _missingFeatures.add(MissingBrowserFeature.dedicatedWorkers);
        return;
      }

      final (endpoint, channel) = await createChannel();
      ConnectRequest(endpoint: endpoint, requestId: 0).sendToWorker(dedicated);

      _connectionToDedicated =
          WorkerConnection(channel.injectErrorsFrom(dedicated));
    } else {
      _missingFeatures.add(MissingBrowserFeature.dedicatedWorkers);
    }
  }

  Future<void> _startShared() async {
    if (globalContext.has('SharedWorker')) {
      final SharedWorker shared;
      try {
        shared = SharedWorker(workerUri.toString().toJS);
      } on Object {
        _missingFeatures.add(MissingBrowserFeature.sharedWorkers);
        return;
      }

      shared.port.start();

      final (endpoint, channel) = await createChannel();
      ConnectRequest(endpoint: endpoint, requestId: 0).sendToPort(shared.port);

      _connectionToShared = WorkerConnection(channel.injectErrorsFrom(shared));
    } else {
      _missingFeatures.add(MissingBrowserFeature.sharedWorkers);
    }
  }

  Future<WorkerConnection> _connectToDedicatedInShared() {
    return _startWorkersLock.synchronized(() async {
      if (_connectionToDedicatedInShared case final conn?) {
        return conn;
      }

      final (endpoint, channel) = await createChannel();
      await _connectionToShared!.sendRequest(
          ConnectRequest(requestId: 0, endpoint: endpoint),
          MessageType.simpleSuccessResponse);

      return _connectionToDedicatedInShared = WorkerConnection(channel);
    });
  }

  Future<WorkerConnection> _connectToLocal() async {
    return _startWorkersLock.synchronized(() async {
      if (_connectionToLocal case final conn?) {
        return conn;
      }

      final local = Local();
      final (endpoint, channel) = await createChannel();
      WorkerRunner(_localController, environment: local).handleRequests();
      local
          .addTopLevelMessage(ConnectRequest(requestId: 0, endpoint: endpoint));

      return _connectionToLocal = WorkerConnection(channel);
    });
  }

  @override
  Future<void> deleteDatabase(
      {required String name, required StorageMode storage}) async {
    switch (storage) {
      case StorageMode.opfs:
        await SimpleOpfsFileSystem.deleteFromStorage(pathForOpfs(name));
      case StorageMode.indexedDb:
        await IndexedDbFileSystem.deleteDatabase(name);
      case StorageMode.inMemory:
    }
  }

  @override
  Future<FeatureDetectionResult> runFeatureDetection(
      {String? databaseName}) async {
    await startWorkers();

    final existing = <ExistingDatabase>{};
    final available = <(StorageMode, AccessMode)>[];
    var workersReportedIndexedDbSupport = false;

    Future<void> dedicatedCompatibilityCheck(
        WorkerConnection connection) async {
      SimpleSuccessResponse response;
      try {
        response = await connection.sendRequest(
          CompatibilityCheck(
            requestId: 0,
            type: MessageType.dedicatedCompatibilityCheck,
            databaseName: databaseName,
          ),
          MessageType.simpleSuccessResponse,
        );
      } on Object {
        return;
      }

      final result = CompatibilityResult.fromJS(response.response as JSObject);
      existing.addAll(result.existingDatabases);
      available.add((StorageMode.inMemory, AccessMode.throughDedicatedWorker));

      if (result.canUseIndexedDb) {
        available
            .add((StorageMode.indexedDb, AccessMode.throughDedicatedWorker));

        workersReportedIndexedDbSupport = true;
      } else {
        _missingFeatures.add(MissingBrowserFeature.indexedDb);
      }

      // For the OPFS storage layer in dedicated workers, we're spawning two
      // nested workers communicating through a synchronous channel created by
      // Atomics and SharedArrayBuffers.
      if (result.canUseOpfs &&
          result.supportsSharedArrayBuffers &&
          result.dedicatedWorkersCanNest) {
        available.add((StorageMode.opfs, AccessMode.throughDedicatedWorker));
      } else {
        if (!result.canUseOpfs) {
          _missingFeatures.add(MissingBrowserFeature.fileSystemAccess);
        }
        if (!result.supportsSharedArrayBuffers) {
          _missingFeatures.add(MissingBrowserFeature.sharedArrayBuffers);
        }
        if (!result.dedicatedWorkersCanNest) {
          _missingFeatures.add(MissingBrowserFeature.dedicatedWorkersCanNest);
        }
      }
    }

    Future<void> sharedCompatibilityCheck(WorkerConnection connection) async {
      SimpleSuccessResponse response;
      try {
        response = await connection.sendRequest(
          CompatibilityCheck(
            requestId: 0,
            type: MessageType.sharedCompatibilityCheck,
            databaseName: databaseName,
          ),
          MessageType.simpleSuccessResponse,
        );
      } on Object {
        return;
      }

      final result = CompatibilityResult.fromJS(response.response as JSObject);

      if (result.canUseIndexedDb) {
        workersReportedIndexedDbSupport = true;
        available.add((StorageMode.indexedDb, AccessMode.throughSharedWorker));
      } else {
        _missingFeatures.add(MissingBrowserFeature.indexedDb);
      }

      if (result.canUseOpfs) {
        available.add((StorageMode.opfs, AccessMode.throughSharedWorker));
      } else if (result.sharedCanSpawnDedicated) {
        // Only report OPFS as unavailable if we can spawn dedicated workers.
        // If we can't, it's known that we can't use OPFS.
        _missingFeatures.add(MissingBrowserFeature.fileSystemAccess);
      }

      available.add((StorageMode.inMemory, AccessMode.throughSharedWorker));
      if (!result.sharedCanSpawnDedicated) {
        _missingFeatures
            .add(MissingBrowserFeature.dedicatedWorkersInSharedWorkers);
      }
    }

    if (_connectionToDedicated case final dedicated?) {
      await dedicatedCompatibilityCheck(dedicated);
    }
    if (_connectionToShared case final shared?) {
      await sharedCompatibilityCheck(shared);
    }

    available.add((StorageMode.inMemory, AccessMode.inCurrentContext));
    if (workersReportedIndexedDbSupport || await checkIndexedDbSupport()) {
      // If the workers can use IndexedDb, so can we.
      available.add((StorageMode.indexedDb, AccessMode.inCurrentContext));
    }

    return FeatureDetectionResult(
      missingFeatures: _missingFeatures.toList(),
      existingDatabases: existing.toList(),
      availableImplementations: available,
    );
  }

  Future<Database> connectToExisting(SqliteWebEndpoint endpoint) async {
    final channel = WorkerConnection(
        WebEndpoint(port: endpoint.$1, lockName: endpoint.$2).connect());

    return RemoteDatabase(
      connection: channel,
      // The database id for this pre-existing connection is always zero.
      // It gets assigned by the worker handling the OpenAdditonalConnection
      // request.
      databaseId: 0,
    );
  }

  @override
  Future<Database> connect(String name, StorageMode type, AccessMode access,
      {bool onlyOpenVfs = false}) async {
    await startWorkers();

    WorkerConnection connection;
    bool shared;
    switch (access) {
      case AccessMode.throughSharedWorker:
        if (type == StorageMode.opfs) {
          // Shared workers don't support OPFS, but we can spawn a dedicated
          // worker inside of the shared worker and connect to that one.
          connection = await _connectToDedicatedInShared();
        } else {
          connection = _connectionToShared!;
        }

        shared = true;
      case AccessMode.throughDedicatedWorker:
        connection = _connectionToDedicated!;
        shared = false;
      case AccessMode.inCurrentContext:
        connection = await _connectToLocal();
        shared = false;
    }

    final response = await connection.sendRequest(
      OpenRequest(
        requestId: 0,
        wasmUri: wasmUri,
        databaseName: name,
        storageMode: type.resolveToVfs(shared),
        onlyOpenVfs: onlyOpenVfs,
      ),
      MessageType.simpleSuccessResponse,
    );
    return RemoteDatabase(
      connection: connection,
      databaseId: (response.response as JSNumber).toDartInt,
    );
  }

  @override
  Future<ConnectToRecommendedResult> connectToRecommended(String name,
      {bool onlyOpenVfs = false}) async {
    final probed = await runFeatureDetection(databaseName: name);

    // If we have an existing database in storage, we want to keep using that
    // format to avoid data loss (e.g. after a browser update that enables a
    // otherwise preferred storage implementation). In the future, we might want
    // to consider migrating between storage implementations as well.
    final availableImplementations = probed.availableImplementations.toList();

    checkExisting:
    for (final (location, name) in probed.existingDatabases) {
      if (name == name) {
        // If any of the implementations for this location is still availalable,
        // we want to use it instead of another location.
        final locationIsAccessible =
            availableImplementations.any((e) => e.$1 == location);
        if (locationIsAccessible) {
          availableImplementations.removeWhere((e) => e.$1 != location);
          break checkExisting;
        }
      }
    }

    // Enum values are ordered by preferrability, so just pick the best option
    // left.
    availableImplementations.sort(preferrableMode);

    final (storage, access) = availableImplementations.firstOrNull ??
        (StorageMode.inMemory, AccessMode.inCurrentContext);
    final database =
        await connect(name, storage, access, onlyOpenVfs: onlyOpenVfs);

    return ConnectToRecommendedResult(
      database: database,
      features: probed,
      storage: storage,
      access: access,
    );
  }

  /// Compares available ways to access databases by the performance and
  /// and reliability of the implementation.
  ///
  /// Returns negative values if `a` is more preferrable than `b` and positive
  /// values if `b` is more preferrable than `a`.
  static int preferrableMode(
      (StorageMode, AccessMode) a, (StorageMode, AccessMode) b) {
    // First, prefer OPFS (an actual file system API) over IndexedDB, a custom
    // file system implementation.
    if (a.$1 != b.$1) {
      return a.$1.index.compareTo(b.$1.index);
    }

    // In a storage API, prefer shared workers which cause less contention
    // because we can actually share database resources between tabs.
    return a.$2.index.compareTo(b.$2.index);
  }
}

extension on StorageMode {
  FileSystemImplementation resolveToVfs(bool shared) {
    return switch (this) {
      StorageMode.opfs => shared
          ? FileSystemImplementation.opfsShared
          : FileSystemImplementation.opfsLocks,
      StorageMode.indexedDb => FileSystemImplementation.indexedDb,
      StorageMode.inMemory => FileSystemImplementation.inMemory,
    };
  }
}
