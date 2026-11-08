@Tags(['ffi'])
library;

import 'dart:isolate';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  // When an isolate is killed, the VM runs the native finalizers of every
  // object the isolate still owns. A kill can arrive while a statement is
  // being closed, and the statement must then not be finalized a second time.
  test('killing an isolate while it closes statements', () async {
    for (var i = 0; i < 300; i++) {
      final ready = ReceivePort();
      final exit = ReceivePort();
      final isolate = await Isolate.spawn(
        _prepareAndCloseForever,
        ready.sendPort,
        onExit: exit.sendPort,
      );
      await ready.first;
      await Future<void>.delayed(Duration(microseconds: (i * 37) % 2000));
      isolate.kill(priority: Isolate.immediate);
      await exit.first;
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

void _prepareAndCloseForever(SendPort ready) {
  final db = sqlite3.openInMemory();
  ready.send(null);
  for (var i = 0; ; i++) {
    final stmt = db.prepare('SELECT ?');
    stmt.select([i]);
    stmt.close();
  }
}
