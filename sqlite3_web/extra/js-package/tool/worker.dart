import 'dart:js_interop';

import 'package:sqlite3/src/database.dart';
import 'package:sqlite3/src/wasm/sqlite3.dart';
import 'package:sqlite3_web/sqlite3_web.dart';

void main() {
  WebSqlite.workerEntrypoint(controller: _DefaultDatabaseController());
}

final class _DefaultDatabaseController extends DatabaseController {
  @override
  Future<JSAny?> handleCustomRequest(
    ClientConnection connection,
    CustomClientRequest request,
  ) async {
    return null;
  }

  @override
  Future<WasmSqlite3> loadWasmModule(
    String uri, {
    Map<String, String>? headers,
  }) {
    return WasmSqlite3.loadFromUrlString(uri, headers: headers);
  }

  @override
  Future<WorkerDatabase> openDatabase(
    WasmSqlite3 sqlite3,
    String path,
    String vfs,
    JSAny? additionalData,
  ) async {
    final options = additionalData == null
        ? null
        : additionalData as AdditionalOpenOptions;
    if (options != null && options.useMultipleCiphersVfs) {
      vfs = 'multipleciphers-$vfs';
    }

    return _DefaultDatabase(sqlite3.open(path, vfs: vfs));
  }
}

final class _DefaultDatabase extends WorkerDatabase {
  @override
  final CommonDatabase database;

  _DefaultDatabase(this.database);

  @override
  Future<JSAny?> handleCustomRequest(
    ClientConnection connection,
    CustomClientDatabaseRequest request,
  ) async {
    return null;
  }
}

@JS()
@anonymous
extension type AdditionalOpenOptions._(JSObject _) implements JSObject {
  external factory AdditionalOpenOptions({required bool useMultipleCiphersVfs});

  external bool get useMultipleCiphersVfs;
}
