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
      ..execute('CREATE TABLE entries (content TEXT);')
      ..execute('CREATE TABLE other (content INTEGER);');
  });
  tearDown(() => database.dispose());

  test('enabled by default', () {
    expect(Session(database).enabled, isTrue);
  });

  test('isEmpty', () {
    final session = Session(database);
    expect(session.isEmpty, isTrue);
    expect(session.isNotEmpty, isFalse);

    // Change without attaching session
    database.execute('INSERT INTO entries DEFAULT VALUES;');
    expect(session.isEmpty, isTrue);

    session.attach();
    database.execute('INSERT INTO entries VALUES (?);', ['my first entry']);

    expect(session.isEmpty, isFalse);
    expect(session.isNotEmpty, isTrue);
  });
}
