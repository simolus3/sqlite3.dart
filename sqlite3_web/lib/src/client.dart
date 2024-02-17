import 'dart:async';
import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:web/web.dart' hide Response, Request, FileSystem, Notification;

import 'api.dart';
import 'channel.dart';
import 'protocol.dart';

final class RemoteDatabase implements Database {
  final WorkerConnection connection;
  final int databaseId;

  StreamSubscription<Notification>? _notificationSubscription;
  final StreamController<SqliteUpdate> _updates = StreamController.broadcast();

  RemoteDatabase({required this.connection, required this.databaseId}) {
    _updates
      ..onListen = (() {
        _notificationSubscription ??=
            connection.notifications.stream.listen((notification) {
          if (notification case UpdateNotification()) {
            if (notification.databaseId == databaseId) {
              _updates.add(notification.update);
            }
          }
        });

        _requestUpdates(true);
      })
      ..onCancel = (() {
        _notificationSubscription?.cancel();
        _notificationSubscription = null;

        _requestUpdates(false);
      });
  }

  void _requestUpdates(bool sendUpdates) {
    connection.sendRequest(
      UpdateStreamRequest(
          action: sendUpdates, requestId: 0, databaseId: databaseId),
      MessageType.simpleSuccessResponse,
    );
  }

  @override
  Future<void> dispose() async {
    _updates.close();
    await connection.sendRequest(
        CloseDatabase(requestId: 0, databaseId: databaseId),
        MessageType.simpleSuccessResponse);
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
  FileSystem get fileSystem => throw UnimplementedError();

  @override
  Future<int> get lastInsertRowId async {
    final result = await select('select last_insert_rowid();');
    return result.single[0] as int;
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
  Future<int> get userVersion async {
    final result = await select('pragma user_version;');
    return result.single[0] as int;
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
  final Worker _worker;
  final Uri wasmUri;

  DatabaseClient(this._worker, this.wasmUri);

  @override
  Future<Database> connect(
      String name, StorageMode type, AccessMode access) async {
    final (endpoint, channel) = await createChannel();
    endpoint.postToWorker(_worker);

    await Future.delayed(Duration(milliseconds: 100));

    final connection = WorkerConnection(channel);
    final data = await connection.sendRequest(
      OpenRequest(
        requestId: 0,
        wasmUri: wasmUri,
        databaseName: name,
        storageMode: type,
      ),
      MessageType.simpleSuccessResponse,
    );

    return RemoteDatabase(
        connection: connection,
        databaseId: (data.response as JSNumber).toDartInt);
  }
}
