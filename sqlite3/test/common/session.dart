import 'dart:async';

import 'package:sqlite3/common.dart';
import 'package:test/test.dart';

void testSession(
  FutureOr<CommonSqlite3> Function() loadSqlite,
) {
  late CommonSqlite3 sqlite3;
  late CommonDatabase database;

  setUpAll(() async => sqlite3 = await loadSqlite());
  setUp(() {
    database = sqlite3.openInMemory();

    database
      ..execute('CREATE TABLE entries (id INTEGER PRIMARY KEY, content TEXT);')
      ..execute(
          'CREATE TABLE other (id INTEGER PRIMARY KEY, content INTEGER);');
  });
  tearDown(() => database.dispose());

  test('enabled by default', () {
    final session = Session(database);
    expect(session.enabled, isTrue);
  });

  test('isEmpty', () {
    final session = Session(database);
    expect(session.isEmpty, isTrue);
    expect(session.isNotEmpty, isFalse);

    // Change without attaching session
    database.execute('INSERT INTO entries DEFAULT VALUES;');
    expect(session.isEmpty, isTrue);

    session.attach();
    database.execute(
        'INSERT INTO entries (content) VALUES (?);', ['my first entry']);

    expect(session.isEmpty, isFalse);
    expect(session.isNotEmpty, isTrue);
  });

  test('attaching to some tables only', () {
    final session = Session(database);
    expect(session.isEmpty, isTrue);
    session.attach('entries');
    database
        .execute('INSERT INTO other (content) VALUES (?);', ['ignored table']);

    expect(session.isEmpty, isTrue);
  });

  test('iterator', () {
    final session = Session(database)..attach();
    database
      ..execute('INSERT INTO entries (content) VALUES (?);', ['a'])
      ..execute('UPDATE entries SET content = ?', ['b']);

    final changeset = session.changeset();
    expect(changeset.bytes, isNotEmpty);
    expect(changeset, [
      isOp(
        operation: SqliteUpdateKind.insert,
        oldValues: isNull,
        newValues: [1, 'b'],
      )
    ]);
  });

  test('changeset invert', () {
    final session = Session(database)..attach();
    database.execute('INSERT INTO entries (content) VALUES (?);', ['a']);

    final changeset = session.changeset();
    final inverted = -changeset;
    expect(inverted, [
      isOp(
          operation: SqliteUpdateKind.delete,
          oldValues: [1, 'a'],
          newValues: null)
    ]);

    expect(database.select('SELECT * FROM entries'), isNotEmpty);
    inverted.applyTo(database);
    expect(database.select('SELECT * FROM entries'), isEmpty);

    // Full changeset should be empty after applying a and -a
    expect(session.changeset(), isEmpty);
  });

  test('apply changeset', () {
    final session = Session(database)..attach();
    database.execute('INSERT INTO entries (content) VALUES (?);', ['a']);
    final changeset = session.changeset();
    session.delete();

    database.execute('DELETE FROM entries');
    changeset.applyTo(database);

    expect(database.select('SELECT * FROM entries'), [
      {'id': 1, 'content': 'a'}
    ]);
  });

  test('apply patchset', () {
    final session = Session(database)..attach();
    database.execute('INSERT INTO entries (content) VALUES (?);', ['a']);
    final patchset = session.patchset();
    session.delete();

    database.execute('DELETE FROM entries');
    patchset.applyTo(database);

    expect(database.select('SELECT * FROM entries'), [
      {'id': 1, 'content': 'a'}
    ]);
  });

  test('diff', () {
    var session = Session(database);
    database.execute('INSERT INTO entries (content) VALUES (?);', ['a']);

    database
      ..execute("ATTACH ':memory:' AS another;")
      ..execute(
          'CREATE TABLE another.entries (id INTEGER PRIMARY KEY, content TEXT);')
      ..execute('INSERT INTO another.entries (content) VALUES (?);', ['b']);

    session = Session(database)..diff('another', 'entries');
    final changeset = session.changeset();
    expect(changeset, [
      isOp(
          operation: SqliteUpdateKind.update,
          oldValues: [1, 'b'],
          newValues: [1, 'a'])
    ]);
  }, skip: "TODO: Figure out what I'm dong wrong");
}

TypeMatcher<ChangesetOperation> isOp({
  Object? table = 'entries',
  Object? columnCount = 2,
  required Object? operation,
  required Object? oldValues,
  required Object? newValues,
}) {
  return isA<ChangesetOperation>()
      .having((e) => e.table, 'table', table)
      .having((e) => e.columnCount, 'colummCount', columnCount)
      .having((e) => e.operation, 'operation', operation)
      .having((e) => e.oldValues, 'oldValues', oldValues)
      .having((e) => e.newValues, 'newValues', newValues);
}
