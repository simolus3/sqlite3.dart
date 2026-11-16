@Tags(['wasm'])
library;

import 'dart:js_interop';

import 'package:sqlite3/common.dart';
import 'package:sqlite3/src/wasm/injected_values.dart';
import 'package:test/test.dart';
import 'package:web/web.dart' as web;

import '../common/traces.dart';
import 'utils.dart';

void main() {
  testTraces(loadSqlite3);

  test('decodes profile durations beyond 32 bits', () {
    final memory = web.Memory(web.MemoryDescriptor(initial: 1));
    final callbacks = DartBridgeCallbacks()..memory = memory;
    final events = <SqliteTrace>[];
    int hook(SqliteTrace event) {
      events.add(event);
      return 0;
    }

    const payload = 8;
    const statementAddress = 42;

    // Low and high words of known nanosecond counts. Include a low word
    // with its sign bit set, and a value with fractional microseconds.
    for (final (lo, hi, microseconds) in [
      (0, 0, 0),
      (3000000000, 0, 3000000),
      (705032827, 1, 5000000),
      (2205032704, 1, 6500000),
      (1410065408, 2, 10000000),
    ]) {
      memory.buffer.toDart.asUint32List(payload, 2)
        ..[0] = lo
        ..[1] = hi;

      expect(
        callbacks.dispatchTraceHook(
          hook.toExternalReference,
          SQLITE_TRACE_PROFILE,
          statementAddress,
          payload,
        ),
        0,
      );
      final profile = events.last as SqliteTraceProfile;
      expect(profile.duration, Duration(microseconds: microseconds));
      expect(profile.statementAddress, statementAddress);
    }
  });
}
