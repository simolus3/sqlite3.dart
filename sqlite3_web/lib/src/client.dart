import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:web/web.dart' hide Response, Request, FileSystem;

import 'api.dart';
import 'channel.dart';
import 'protocol.dart';

final class RemoteDatabase implements Database {
  final WorkerConnection connection;
  final int databaseId;

  RemoteDatabase({required this.connection, required this.databaseId});

  @override
  Future<void> dispose() {
    // TODO: implement dispose
    throw UnimplementedError();
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
  Stream<SqliteUpdate> get updates => throw UnimplementedError();

  @override
  Future<int> get userVersion async {
    final result = await select('pragma user_version;');
    return result.single[0] as int;
  }
}

final class WorkerConnection extends ProtocolChannel {
  WorkerConnection(super.channel);

  @override
  Future<Response> handleRequest(Request request) {
    // TODO: implement handleRequest
    throw UnimplementedError();
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
