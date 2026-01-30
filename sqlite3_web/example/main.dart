import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sqlite3_web/sqlite3_web.dart';

void main() async {
  final sqlite = WebSqlite.open(
    workers: WorkerConnector.defaultWorkers(Uri.parse('worker.dart.js')),
    wasmModule: Uri.parse('sqlite3.wasm'),
  );

  final features = await sqlite.runFeatureDetection();
  print('got features: $features');

  globalContext['open'] = (JSString name, JSString implementation) {
    return Future(() async {
      final database = await sqlite.connect(
        name.toDart,
        DatabaseImplementation.values.byName(implementation.toDart),
      );

      database.updates.listen((update) {
        print('Update on $name: $update');
      });

      return database.toJSBox;
    }).toJS;
  }.toJS;

  globalContext['execute'] = (JSBoxedDartObject database, JSString sql) {
    return Future(() async {
      await (database.toDart as Database).execute(sql.toDart);
    }).toJS;
  }.toJS;
}
