import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:sqlite3_web/sqlite3_web.dart';
import 'package:sqlite3_web/src/client.dart';
import 'package:web/web.dart';

import 'controller.dart';

final sqlite3WasmUri = Uri.parse('sqlite3.wasm');
final workerUri = Uri.parse('worker.dart.js');
const databaseName = 'database';
const additionalOptions = 'test-additional-options';

WebSqlite? webSqlite;

Database? database;
int updates = 0;
int commits = 0;
int rollbacks = 0;
bool listeningForUpdates = false;

void main() {
  _addCallbackForWebDriver('isDart2wasm', (_) async {
    const isWasm = bool.fromEnvironment('dart.tool.dart2wasm');
    return isWasm.toJS;
  });
  _addCallbackForWebDriver('detectImplementations', _detectImplementations);
  _addCallbackForWebDriver('close', (arg) async {
    await database?.dispose();
    return null;
  });
  _addCallbackForWebDriver('get_updates', (arg) async {
    listenForUpdates();
    return [
      updates.toJS,
      commits.toJS,
      rollbacks.toJS,
    ].toJS;
  });
  _addCallbackForWebDriver('open', (arg) => _open(arg, false));
  _addCallbackForWebDriver('open_only_vfs', (arg) => _open(arg, true));
  _addCallbackForWebDriver('exec', _exec);
  _addCallbackForWebDriver('test_second', (arg) async {
    final sqlite = initializeSqlite();
    // Open one database to occupy the database id of zero in the worker
    final unused = await sqlite.connect(
        'a', StorageMode.inMemory, AccessMode.throughSharedWorker);
    await unused.execute('CREATE TABLE unused (bar TEXT);');

    // Then open another one
    final first = await sqlite.connect(
            'b', StorageMode.inMemory, AccessMode.throughSharedWorker)
        as RemoteDatabase;
    await first.execute('CREATE TABLE foo (bar TEXT);');

    final endpoint = await first.additionalConnection();
    final second = await WebSqlite.connectToPort(endpoint) as RemoteDatabase;

    // First and second should have different internal ids (that's what the
    // setup with the unused database was trying to accomplish).
    if (first.databaseId == second.databaseId) {
      return 'Unexpected same id'.toJS;
    }

    await second.execute('SELECT * FROM foo;');

    var receivedUpdates = 0;
    second.updates.listen((_) => receivedUpdates++);

    await first.execute('INSERT INTO foo VALUES (?)', ['a']);
    await unused.execute('INSERT INTO unused VALUES (?)', ['a']);

    await Future.delayed(const Duration(milliseconds: 200));

    await unused.dispose();
    await first.dispose();
    await second.dispose();
    // This should have received the update from the first database without
    // receiving the one from the unrelated database.
    return (receivedUpdates == 1).toJS;
  });
  _addCallbackForWebDriver('assert_file', (arg) async {
    final vfs = database!.fileSystem;

    final exists = await vfs.exists(FileType.database);
    print('exists: $exists');
    if (exists != bool.parse(arg!)) {
      return false.toJS;
    }

    if (exists) {
      // Try reading file contents
      final buffer = await vfs.readFile(FileType.database);
      return buffer.length.toJS;
    }

    return true.toJS;
  });
  _addCallbackForWebDriver('flush', (arg) async {
    final vfs = database!.fileSystem;
    await vfs.flush();
    return true.toJS;
  });
  _addCallbackForWebDriver('delete_db', (arg) async {
    final storage = StorageMode.values.byName(arg!);
    await initializeSqlite()
        .deleteDatabase(name: databaseName, storage: storage);
    return true.toJS;
  });
  _addCallbackForWebDriver('check_read_write', (arg) async {
    final vfs = database!.fileSystem;

    final bytes = Uint8List(1024 * 128);
    for (var i = 0; i < 128; i++) {
      bytes[i * 1024] = i;
    }

    await vfs.writeFile(FileType.database, bytes);
    await vfs.flush();
    final result = await vfs.readFile(FileType.database);
    if (result.length != bytes.length) {
      return 'length mismatch'.toJS;
    }

    for (var i = 0; i < 128; i++) {
      if (result[i * 1024] != i) {
        return 'mismatch, i=$i, byte ${result[i * 1024]}'.toJS;
      }
    }

    return null;
  });
  _addCallbackForWebDriver('custom_request', (arg) async {
    return database!.customRequest(null);
  });

  document.getElementById('selfcheck')?.onClick.listen((event) async {
    print('starting');
    final sqlite = initializeSqlite();
    final database = await sqlite.connectToRecommended(databaseName);

    print('selected storage: ${database.storage} through ${database.access}');
    print('missing features: ${database.features.missingFeatures}');
  });

  document.body!.appendChild(HTMLDivElement()..id = 'ready');
}

void _addCallbackForWebDriver(
    String name, Future<JSAny?> Function(String?) impl) {
  globalContext.setProperty(
    name.toJS,
    (JSString? arg, JSFunction callback) {
      Future(() async {
        JSAny? result;

        try {
          result = await impl(arg?.toDart);
        } catch (e, s) {
          final console = globalContext['console']! as JSObject;
          console.callMethod(
              'error'.toJS, e.toString().toJS, s.toString().toJS);
        }

        callback.callAsFunction(null, result);
      });
    }.toJS,
  );
}

WebSqlite initializeSqlite() {
  return webSqlite ??= WebSqlite.open(
    worker: workerUri,
    wasmModule: sqlite3WasmUri,
    controller: ExampleController(isInWorker: false),
    handleCustomRequest: (request) async {
      return 21.toJS;
    },
  );
}

Future<JSString> _detectImplementations(String? _) async {
  final instance = initializeSqlite();
  final result = await instance.runFeatureDetection(databaseName: 'database');

  return json.encode({
    'impls': result.availableImplementations
        .map((r) => [r.$1.name, r.$2.name])
        .toList(),
    'missing': result.missingFeatures.map((r) => r.name).toList(),
    'existing': result.existingDatabases.map((r) => [r.$1.name, r.$2]).toList(),
  }).toJS;
}

Future<JSAny?> _open(String? implementationName, bool onlyOpenVfs) async {
  final sqlite = initializeSqlite();
  Database db;
  var returnValue = implementationName;

  if (implementationName != null) {
    final split = implementationName.split(':');

    db = await sqlite.connect(
      databaseName,
      StorageMode.values.byName(split[0]),
      AccessMode.values.byName(split[1]),
      onlyOpenVfs: onlyOpenVfs,
      additionalOptions: additionalOptions.toJS,
    );
  } else {
    final result = await sqlite.connectToRecommended(
      databaseName,
      onlyOpenVfs: onlyOpenVfs,
      additionalOptions: additionalOptions.toJS,
    );
    db = result.database;
    returnValue = '${result.storage.name}:${result.access.name}';
  }

  database = db;

  // Make sure it works!
  if (!onlyOpenVfs) {
    final rows = await db
        .select('SELECT database_host() as host, additional_data() as data;');
    if (rows.length != 1) {
      throw 'unexpected row count';
    }
    final row = rows[0];
    if (row['data'] != additionalOptions) {
      throw 'unexpected data: $row';
    }

    listenForUpdates();
  }

  return returnValue?.toJS;
}

void listenForUpdates() {
  if (!listeningForUpdates) {
    listeningForUpdates = true;
    database!.updates.listen((_) => updates++);
    database!.commits.listen((_) => commits++);
    database!.rollbacks.listen((_) => rollbacks++);
  }
}

Future<JSAny?> _exec(String? sql) async {
  await database!.execute(sql!);
  return null;
}
