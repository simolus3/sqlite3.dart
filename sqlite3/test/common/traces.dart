import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:test/test.dart';

void testTraces(FutureOr<CommonSqlite3> Function() loadSqlite) {
  late CommonSqlite3 sqlite3;
  late CommonDatabase database;

  setUpAll(() async => sqlite3 = await loadSqlite());
  setUp(() => database = sqlite3.openInMemory());
  tearDown(() => database.close());

  /// Starts tracing, collecting reported events into [events].
  void traceInto(
    List<SqliteTrace> events, {
    bool statement = true,
    bool row = true,
    bool profile = true,
  }) {
    database.trace = SqliteTraceCallback(
      (trace) {
        events.add(trace);
        return 0;
      },
      statement: statement,
      row: row,
      profile: profile,
    );
  }

  test('all categories disabled is rejected', () {
    expect(
      () => database.trace = SqliteTraceCallback(
        (_) => 0,
        statement: false,
        row: false,
        profile: false,
      ),
      throwsArgumentError,
    );
  });

  test('reports statement and profile events', () {
    database.execute('CREATE TABLE tbl (a)');
    final events = <SqliteTrace>[];
    traceInto(events, row: false);

    database.execute('INSERT INTO tbl DEFAULT VALUES');

    expect(events, hasLength(2));
    final statement = events.first as SqliteTraceStatement;
    final profile = events.last as SqliteTraceProfile;
    expect(statement.sql, 'INSERT INTO tbl DEFAULT VALUES');
    // The address identifies a native statement that is currently running
    // and hence is never zero. Passing the wrong argument of the native
    // trace callback would surface as a null address here.
    expect(statement.statementAddress, greaterThan(0));
    expect(profile.statementAddress, statement.statementAddress);
    expect(profile.duration, greaterThanOrEqualTo(Duration.zero));
  });

  test('reports events in order and synchronously', () {
    database.execute('CREATE TABLE tbl (a)');
    database.execute('INSERT INTO tbl DEFAULT VALUES');
    database.execute('INSERT INTO tbl DEFAULT VALUES');

    final events = <SqliteTrace>[];
    traceInto(events);

    database.execute('SELECT * FROM tbl');

    // A statement reports its start, one event per row it returns and its
    // completion - in that order, and with a stable address.
    expect(events.map((e) => e.runtimeType), [
      SqliteTraceStatement,
      SqliteTraceRow,
      SqliteTraceRow,
      SqliteTraceProfile,
    ]);
    final statement = events.first as SqliteTraceStatement;
    for (final event in events.whereType<SqliteTraceWithStatement>()) {
      expect(event.statementAddress, statement.statementAddress);
    }

    // Events are delivered synchronously: no event loop turn happened
    // between running the statement and this expectation.
    expect(events, hasLength(4));
  });

  test('filters by event category', () {
    database.execute('CREATE TABLE tbl (a)');
    database.execute('INSERT INTO tbl DEFAULT VALUES');

    final events = <SqliteTrace>[];
    traceInto(events, statement: false, row: false);

    database.execute('INSERT INTO tbl DEFAULT VALUES');

    expect(events, hasLength(1));
    expect(events.single, isA<SqliteTraceProfile>());
  });

  test('re-registering replaces the callback and its categories', () {
    database.execute('CREATE TABLE tbl (a)');
    database.execute('INSERT INTO tbl DEFAULT VALUES');

    final statements = <SqliteTraceStatement>[];
    database.trace = SqliteTraceCallback(
      (trace) {
        statements.add(trace as SqliteTraceStatement);
        return 0;
      },
      row: false,
      profile: false,
    );

    database.execute('SELECT * FROM tbl');
    expect(statements, hasLength(1));

    // The second registration only asks for row events, replacing the first.
    final rows = <SqliteTraceRow>[];
    final second = SqliteTraceCallback(
      (trace) {
        rows.add(trace as SqliteTraceRow);
        return 0;
      },
      statement: false,
      profile: false,
    );
    expect(database.trace, isNot(second));
    database.trace = second;
    expect(database.trace, same(second));

    statements.clear();
    database.execute('SELECT * FROM tbl');

    expect(statements, isEmpty);
    expect(rows, hasLength(1));
  });

  test('stops reporting events after clearing the callback', () {
    database.execute('CREATE TABLE tbl (a)');

    final events = <SqliteTrace>[];
    traceInto(events);
    expect(database.trace, isNotNull);
    database.execute('INSERT INTO tbl DEFAULT VALUES');
    expect(events, isNotEmpty);

    database.trace = null;
    expect(database.trace, isNull);
    events.clear();

    database.execute('INSERT INTO tbl DEFAULT VALUES');
    expect(events, isEmpty);

    // Clearing without an active callback is a no-op.
    database.trace = null;
  });

  test('exceptions and return values from the callback are not fatal', () {
    database.execute('CREATE TABLE tbl (a)');

    database.trace = SqliteTraceCallback((_) {
      throw StateError('nope');
    });

    expect(
      () => database.execute('INSERT INTO tbl DEFAULT VALUES'),
      returnsNormally,
    );

    database.trace = SqliteTraceCallback((_) => 42);
    expect(
      () => database.execute('INSERT INTO tbl DEFAULT VALUES'),
      returnsNormally,
    );
  });

  test('database can be disposed while tracing', () {
    database.execute('CREATE TABLE tbl (a)');
    database.trace = SqliteTraceCallback((_) => 0);
    database.execute('INSERT INTO tbl DEFAULT VALUES');

    database.close();
  });
}
