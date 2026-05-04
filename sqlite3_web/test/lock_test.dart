@TestOn('browser')
library;

import 'dart:async';

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
}
