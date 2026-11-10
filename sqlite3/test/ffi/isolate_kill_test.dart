@Tags(['ffi'])
library;

import 'dart:isolate';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  // Killing an isolate while it attaches a finalizer can crash the VM during
  // isolate shutdown, independent of this package. Re-enable these tests once
  // the fix for that is in a released SDK.
  const vmCrash =
      'Crashes the Dart VM: https://github.com/dart-lang/sdk/issues/64897';

  // Regression test for https://github.com/simolus3/sqlite3.dart/issues/437
  test(
    'killing an isolate while it closes statements',
    () => _killRepeatedly(_prepareAndCloseForever),
    timeout: const Timeout(Duration(minutes: 2)),
    skip: vmCrash,
  );

  test(
    'killing an isolate while it opens and closes databases',
    () => _killRepeatedly(_openAndCloseForever),
    timeout: const Timeout(Duration(minutes: 2)),
    skip: vmCrash,
  );
}

/// Spawns an isolate running [entryPoint] and kills it at a random point, many
/// times over. A kill that lands at the wrong moment crashes the whole process.
Future<void> _killRepeatedly(void Function(SendPort) entryPoint) async {
  final random = Random();
  for (var i = 0; i < 300; i++) {
    final ready = ReceivePort();
    final exit = ReceivePort();
    final isolate = await Isolate.spawn(
      entryPoint,
      ready.sendPort,
      onExit: exit.sendPort,
    );
    await ready.first;
    await Future<void>.delayed(Duration(microseconds: random.nextInt(2000)));
    isolate.kill(priority: Isolate.immediate);
    await exit.first;
  }
}

void _prepareAndCloseForever(SendPort ready) {
  final db = sqlite3.openInMemory();
  // Prepare and close one statement before the kill can arrive, so that the
  // statement finalizer is registered with the isolate up front.
  db.prepare('SELECT 1').close();
  ready.send(null);
  for (var i = 0; ; i++) {
    final stmt = db.prepare('SELECT ?');
    stmt.select([i]);
    stmt.close();
  }
}

void _openAndCloseForever(SendPort ready) {
  ready.send(null);
  for (;;) {
    sqlite3.openInMemory().close();
  }
}
