@Tags(['wasm'])
library;

import 'dart:async';

import 'package:sqlite3/src/wasm/async.dart';
import 'package:test/test.dart';

void main() {
  test('does not schedule microtasks with parent zone', () async {
    var didScheduleMicrotask = false;

    await runZoned(
      () {
        return runWithNativeMicrotasks(() async {
          await Future.microtask(() => 0);
        });
      },
      zoneSpecification: ZoneSpecification(
        scheduleMicrotask: (self, parent, zone, f) {
          didScheduleMicrotask = false;
          parent.scheduleMicrotask(zone, f);
        },
      ),
    );

    expect(didScheduleMicrotask, isFalse);
  });

  test('handles errors', () async {
    var didScheduleMicrotask = false;
    Object? caughtError;

    await runZoned(
      () {
        return runWithNativeMicrotasks(() async {
          scheduleMicrotask(() {
            throw 'Expected error';
          });
        });
      },
      zoneSpecification: ZoneSpecification(
        handleUncaughtError: (self, parent, zone, error, stackTrace) {
          caughtError = error;
        },
        scheduleMicrotask: (self, parent, zone, f) {
          didScheduleMicrotask = false;
          parent.scheduleMicrotask(zone, f);
        },
      ),
    );

    expect(didScheduleMicrotask, isFalse);
    expect(caughtError, 'Expected error');
  });
}
