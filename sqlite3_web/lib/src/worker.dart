import 'dart:async';
import 'dart:js_interop';
import 'package:sqlite3/wasm.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web/web.dart' hide Response, Request;

import 'api.dart';
import 'channel.dart';
import 'protocol.dart';

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

  Stream<WebEndpoint> get connectRequests;

  Stream<StreamChannel<Message>> get incomingConnections {
    return connectRequests.asyncMap((endpoint) {
      return endpoint.connect();
    });
  }
}

final class Dedicated extends WorkerEnvironment {
  final DedicatedWorkerGlobalScope scope;

  Dedicated()
      : scope = globalContext as DedicatedWorkerGlobalScope,
        super._();

  @override
  Stream<WebEndpoint> get connectRequests {
    return EventStreamProviders.messageEvent
        .forTarget(scope)
        .map((event) => event.data as WebEndpoint);
  }
}

final class Shared extends WorkerEnvironment {
  final SharedWorkerGlobalScope scope;

  Shared()
      : scope = globalContext as SharedWorkerGlobalScope,
        super._();

  @override
  Stream<WebEndpoint> get connectRequests {
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
            EventStreamProviders.messageEvent.forTarget(scope).listen((event) {
          listener.addSync(event.data as WebEndpoint);
        }));
      }

      subscriptions.add(
          EventStreamProviders.connectEvent.forTarget(scope).listen((event) {
        for (final port in (event as MessageEvent).ports.toDart) {
          handlePort(port as MessagePort);
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

final class _ClientConnection extends ProtocolChannel
    implements ClientConnection {
  final WorkerRunner _runner;
  final List<int> _openedDatabases = [];

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
        _runner.openedDatabases[id]!.decrementRefCount();
      }
    });
  }

  @override
  Future<Response> handleRequest(Request request) async {
    final database = _databaseFor(request);

    switch (request) {
      case CustomRequest():
        JSAny? response;

        if (database != null) {
          response = await (await database.opened)
              .handleCustomRequest(this, request.payload);
        } else {
          response = await _runner._controller
              .handleCustomRequest(this, request.payload);
        }

        return SimpleSuccessResponse(
            requestId: request.requestId, response: response);
      case OpenRequest():
        await _runner.loadWasmModule(request.wasmUri);
        DatabaseState? database;

        try {
          database =
              _runner.findDatabase(request.databaseName, request.storageMode);
          await database.opened;
          _openedDatabases.add(database.id);
          return SimpleSuccessResponse(
              response: database.id.toJS, requestId: request.requestId);
        } catch (e) {
          if (database != null) {
            _openedDatabases.remove(database.id);
            await database.decrementRefCount();
          }

          rethrow;
        }
      case RunQuery():
        final openedDatabase = await database!.opened;

        if (request.returnRows) {
          return RowsResponse(
            resultSet:
                openedDatabase.database.select(request.sql, request.parameters),
            requestId: request.requestId,
          );
        } else {
          openedDatabase.database.execute(request.sql, request.parameters);
          return SimpleSuccessResponse(
              response: null, requestId: request.requestId);
        }
      case FileSystemExistsQuery():
        throw UnimplementedError();
      case FileSystemAccess():
        throw UnimplementedError();
    }
  }

  @override
  Future<JSAny?> customRequest(JSAny? request) async {
    final response = await sendRequest(
        CustomRequest(requestId: 0, payload: request),
        MessageType.simpleSuccessResponse);
    return response.response;
  }

  DatabaseState? _databaseFor(Request request) {
    if (request.databaseId case final id?) {
      if (!_openedDatabases.contains(id)) {
        throw ArgumentError(
            "Connection is referencing database it didn't open.");
      }

      return _runner.openedDatabases[id]!;
    } else {
      return null;
    }
  }
}

final class DatabaseState {
  final WorkerRunner runner;
  final int id;
  final String name;
  final StorageMode mode;
  int refCount = 1;

  Future<WorkerDatabase>? _database;

  DatabaseState(
      {required this.id,
      required this.runner,
      required this.name,
      required this.mode});

  Future<WorkerDatabase> get opened async {
    if (_database == null) {
      final sqlite3 = await runner._sqlite3!;
      final vfsName = 'vfs-web-$id';

      sqlite3.registerVirtualFileSystem(InMemoryFileSystem(name: vfsName));
      _database = runner._controller.openDatabase(sqlite3, vfsName);
    }

    return await _database!;
  }

  Future<void> decrementRefCount() async {
    if (--refCount == 0) {
      await close();
    }
  }

  Future<void> close() async {}
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

  WorkerRunner(this._controller) : _environment = WorkerEnvironment();

  void handleRequests() async {
    await for (final channel in _environment.incomingConnections) {
      _accept(channel);
    }
  }

  void _accept(StreamChannel<Message> channel) {
    final connection = _ClientConnection(
        runner: this, channel: channel, id: _nextConnectionId++);
    _connections.add(connection);
    connection.closed.whenComplete(() => _connections.remove(connection));
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
    }
  }

  DatabaseState findDatabase(String name, StorageMode mode) {
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
    );
  }
}
