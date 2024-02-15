import 'dart:js_interop';
import 'dart:typed_data';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';
import 'package:web/web.dart';

import 'client.dart';
import 'worker.dart';

enum FileType {
  database,
  journal,
}

enum StorageMode {
  // Note: Indices in this enum are used in the protocol, changing them is a
  // backwards-incompatible change.
  opfs,
  indexedDb,
  inMemory,
}

enum AccessMode {
  throughSharedWorker,
  throughDedicatedWorker,
  inCurrentContext,
}

final class RemoteException implements Exception {
  final String message;

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

abstract class Database {
  FileSystem get fileSystem;
  Stream<SqliteUpdate> get updates;

  Future<void> dispose();

  Future<int> get lastInsertRowId;

  Future<int> get userVersion;
  Future<void> setUserVersion(int version);

  Future<void> execute(String sql, [List<Object?> parameters = const []]);
  Future<ResultSet> select(String sql, [List<Object?> parameters = const []]);
}

abstract class HostedDatabase {
  Iterable<ClientConnection> get currentConnections;
  CommonDatabase get database;
  VirtualFileSystem get vfs;
}

abstract class ClientConnection {
  int get id;

  Future<void> get closed;

  Future<JSAny?> customRequest(JSAny? request);
}

abstract class WorkerDatabase {
  CommonDatabase get database;

  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request);
}

abstract base class DatabaseController {
  Future<WasmSqlite3> loadWasmModule(Uri uri,
      {Map<String, String>? headers}) async {
    return WasmSqlite3.loadFromUrl(uri, headers: headers);
  }

  Future<WorkerDatabase> openDatabase(WasmSqlite3 sqlite3, String vfs);

  Future<JSAny?> handleCustomRequest(
      ClientConnection connection, JSAny? request);
}

abstract class WebSqlite {
  Future<Database> connect(String name, StorageMode type, AccessMode access);

  static void workerEntrypoint({
    required DatabaseController controller,
  }) {
    WorkerRunner(controller).handleRequests();
  }

  static Future<WebSqlite> open({
    required Uri worker,
    required Uri wasmModule,
  }) async {
    return DatabaseClient(Worker(worker.path), wasmModule);
  }
}
