@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:sqlite3_web/src/locks.dart';
import 'package:sqlite3_web/src/types.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

void main() {
  group('mutex', () {
    late Mutex mutex;
    setUp(() => mutex = Mutex());

    test('can acquire', () async {
      var inCriticalSectionCount = 0;

      Future<void> testWith(int result) async {
        expect(
          await mutex.withCriticalSection(() async {
            expect(inCriticalSectionCount, 0);
            inCriticalSectionCount++;

            await pumpEventQueue(times: 2);

            inCriticalSectionCount--;
            expect(inCriticalSectionCount, 0);
            return result;
          }),
          result,
        );
      }

      await Future.wait(Iterable.generate(100, testWith));
    });

    test('can abort waiting', () async {
      final hasFirst = Completer<void>();
      final returnFirst = Completer<void>();
      mutex.withCriticalSection(() async {
        hasFirst.complete();
        await returnFirst.future;
      });

      await hasFirst.future;
      final controller = AbortController();
      final expectation = expectLater(
        mutex.withCriticalSection(
          expectAsync0(() {}, count: 0),
          abort: controller.signal,
        ),
        throwsA(isA<AbortException>()),
      );

      await pumpEventQueue();
      controller.abort();
      await expectation;
      returnFirst.complete();
    });

    test('can pass aborted signal', () async {
      await expectLater(
        mutex.withCriticalSection(
          expectAsync0(() {}, count: 0),
          abort: AbortSignal.abort(),
        ),
        throwsA(isA<AbortException>()),
      );
    });
  });

  group('database locks', () {
    test('without inter-context support', () async {
      final locks = DatabaseLocks('foo', false);
      expect(locks.canRunSynchronousBlockDirectly, isTrue);

      await locks.lock(() async {
        expect(locks.canRunSynchronousBlockDirectly, isFalse);
      }, null);
    });

    test('keeps navigator locks after critical section', () async {
      final name = _randomLockName();
      final locks = DatabaseLocks(name, true);
      await locks.lock(() async {}, null);

      // Should keep the outer and inner lock locked at this point.
      expect(await _queryHeldLocks(name), hasLength(2));

      // Stealing the outer lock should release both locks.
      final stolen = await WebLocks.instance!.request(
        locks.outerLockName,
        steal: true,
      );
      stolen.release();

      await pumpEventQueue();
      expect(await _queryHeldLocks(name), isEmpty);
    });

    test('can release navigator locks explicitly', () async {
      final name = _randomLockName();
      final locks = DatabaseLocks(name, true);
      await locks.lock(() async {}, null);
      expect(await _queryHeldLocks(name), hasLength(2));

      await locks.releaseNavigatorLocks();
      await pumpEventQueue();
      expect(await _queryHeldLocks(name), hasLength(0));
    });

    test('can coordinate across multiple instances', () async {
      final name = _randomLockName();
      final a = DatabaseLocks(name, true);
      final b = DatabaseLocks(name, true);

      await a.lock(() async {}, null);
      await b.lock(() async {}, null);
    });
  });
}

String _randomLockName() {
  final buffer = StringBuffer();
  final random = Random();

  for (var i = 0; i < 16; i++) {
    const charCodeSmallA = 97;
    buffer.writeCharCode(charCodeSmallA + random.nextInt(26));
  }

  return buffer.toString();
}

Future<List<String>> _queryHeldLocks(String name) async {
  final queried = await WebLocks.instance!.raw.query().toDart;
  final held = queried.held.toDart;

  return held.map((e) => e.name).where((e) => e.contains(name)).toList();
}
