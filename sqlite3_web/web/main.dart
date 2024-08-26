import 'dart:convert';
import 'dart:html';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:async/async.dart';
import 'package:sqlite3_web/sqlite3_web.dart';

final sqlite3WasmUri = Uri.parse('sqlite3.wasm');
final workerUri = Uri.parse('worker.dart.js');
const databaseName = 'database';

WebSqlite? webSqlite;

Database? database;
StreamQueue<void>? updates;

void main() {
  _addCallbackForWebDriver('detectImplementations', _detectImplementations);
  _addCallbackForWebDriver('close', (arg) async {
    await database?.dispose();
    return null;
  });
  _addCallbackForWebDriver('wait_for_update', _waitForUpdate);
  _addCallbackForWebDriver('open', _open);
  _addCallbackForWebDriver('exec', _exec);

  document.getElementById('selfcheck')?.onClick.listen((event) async {
    print('starting');
    final sqlite = initializeSqlite();
    final database = await sqlite.connectToRecommended(databaseName);

    print('selected storage: ${database.storage} through ${database.access}');
    print('missing features: ${database.features.missingFeatures}');
  });

  document.body!.children.add(DivElement()..id = 'ready');
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

Future<JSAny?> _waitForUpdate(String? _) async {
  await updates!.next;
  return null;
}

Future<JSAny?> _open(String? implementationName) async {
  final sqlite = initializeSqlite();
  Database db;
  var returnValue = implementationName;

  if (implementationName != null) {
    final split = implementationName.split(':');

    db = await sqlite.connect(databaseName, StorageMode.values.byName(split[0]),
        AccessMode.values.byName(split[1]));
  } else {
    final result = await sqlite.connectToRecommended(databaseName);
    db = result.database;
    returnValue = '${result.storage.name}:${result.access.name}';
  }

  // Make sure it works!
  await db.select('SELECT database_host()');

  updates = StreamQueue(db.updates);
  database = db;
  return returnValue?.toJS;
}

Future<JSAny?> _exec(String? sql) async {
  await database!.execute(sql!);
  return null;
}
