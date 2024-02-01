@Tags(['wasm'])
import 'dart:html';

import 'package:http/http.dart' as http;
import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:sqlite3/wasm.dart';
import 'package:test/test.dart';

import 'utils.dart';

void main() {
  for (final throughFetch in [false, true]) {
    group(throughFetch ? 'with fetch' : 'manually', () {
      late WasmSqlite3 sqlite3;

      setUpAll(() async {
        if (throughFetch) {
          sqlite3 = await loadSqlite3();
        } else {
          final channel = spawnHybridUri('/test/wasm/asset_server.dart');
          final port = await channel.stream.first as int;

          final sqliteWasm =
              Uri.parse('http://localhost:$port/example/web/sqlite3.wasm');

          final response = await http.get(sqliteWasm);
          if (response.statusCode != 200) {
            throw StateError(
                'Could not load module (${response.statusCode} ${response.body})');
          }

          sqlite3 = await WasmSqlite3.load(response.bodyBytes);
          sqlite3.registerVirtualFileSystem(InMemoryFileSystem(),
              makeDefault: true);
        }
      });

      test('get version', () {
        final version = sqlite3.version;
        expect(
          version,
          isA<Version>()
              .having((e) => e.libVersion, 'libVersion', startsWith('3.45')),
        );
      });

      test('can use current date', () {
        final db = sqlite3.openInMemory();
        addTearDown(db.dispose);

        final results =
            db.select("SELECT strftime('%s', CURRENT_TIMESTAMP) AS r");
        final row = results.single['r'] as String;

        expect(int.parse(row),
            closeTo(DateTime.now().millisecondsSinceEpoch ~/ 1000, 5));
      });
    });
  }

  group(
    'can be used in workers',
    () {
      late String workerUri;
      late String wasmUri;

      setUpAll(() async {
        final channel = spawnHybridUri('/test/wasm/worker_server.dart');
        final port = await channel.stream.first as int;

        final uri = 'http://localhost:$port/worker.dart.js';
        wasmUri = 'http://localhost:$port/sqlite3.wasm';
        final blob =
            Blob(<String>['importScripts("$uri");'], 'application/javascript');

        workerUri = _createObjectURL(blob);
      });

      // See worker.dart for the supported backends
      for (final backend in ['memory', 'opfs-simple', 'opfs', 'indexeddb']) {
        final requiresSab = backend == 'opfs';
        final missingSab =
            requiresSab && !hasProperty(globalThis, 'SharedArrayBuffer');

        test(
          backend,
          () async {
            final worker = Worker(workerUri);

            worker.onError.listen((event) {
              if (event is ErrorEvent) {
                fail('Error ${event.message} - ${event.error}');
              } else {
                fail(event.toString());
              }
            });
            // Inform the worker about the test we want to run
            worker.postMessage([backend, wasmUri]);

            final response = (await worker.onMessage.first).data as List;
            final status = response[0] as bool;

            if (!status) {
              throw 'Exception in worker: $response';
            }
          },
          skip: missingSab
              ? 'This test requires SharedArrayBuffers that cannot be enabled '
                  'on this platform with a simple `dart test` setup.'
              : null,
          onPlatform: {
            if (backend == 'opfs')
              'chrome || edge':
                  Skip('todo: Always times out in GitHub actions'),
          },
        );
      }
    },
  );
}

@JS('URL.createObjectURL')
external String _createObjectURL(Blob blob);
