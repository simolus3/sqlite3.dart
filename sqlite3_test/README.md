This package provides utilities for accessing SQLite databases in Dart tests.

## Features

Given that SQLite has no external dependencies and runs in the process of your
app, it can easily be used in unit tests (avoiding the hassle of writing mocks
for your database and repositories).

However, being a C library, SQLite is unaware of other Dart utilities typically
used in tests (like a fake time with `package:clock` or a custom file system
based on `package:file`).
When your database queries depend on `CURRENT_TIMESTAMP`, this makes it hard
to reliably test them as `clock.now()` and `CURRENT_TIMESTAMP` would report
different values.

As a solution, this small package makes SQLite easier to integrate into your
tests by providing a [VFS](https://sqlite.org/vfs.html) that will:

1. Make `CURRENT_TIME`, `CURRENT_DATE` and `CURRENT_TIMESTAMP` reflect the time
   returned by `package:clock`.
2. For IO operations, allow providing a `FileSystem` from `package:file`. This
   includes custom implementations and the default one respecting
   `IOOverrides`.

## Usage

This package is intended to be used in tests, so begin by adding a dev
dependency on it:

```
$ dart pub add --dev sqlite3_test
```

You can then use it in tests by creating an instance of `TestSqliteFileSystem`
for your databases:

```dart
import 'package:fake_async/fake_async.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_test/sqlite3_test.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';

void main() {
  late TestSqliteFileSystem vfs;

  setUpAll(() {
    vfs = TestSqliteFileSystem(fs: const LocalFileSystem());
    sqlite3.registerVirtualFileSystem(vfs);
  });
  tearDownAll(() => sqlite3.unregisterVirtualFileSystem(vfs));

  test('my test depending on database time', () {
    final database = sqlite3.openInMemory(vfs: vfs.name);
    addTearDown(database.dispose);

    // The VFS uses package:clock to get the current time, which can be
    // overridden for tests:
    final moonLanding = DateTime.utc(1969, 7, 20, 20, 18, 04);
    FakeAsync(initialTime: moonLanding).run((_) {
      final row = database.select('SELECT unixepoch(current_timestamp)').first;

      expect(row.columnAt(0), -14182916);
    });
  });
}
```

## Limitations

The layer of indirection through Dart will likely make your databases slower.
For this reason, this package is intended to be used in tests (as the overhead
is not a problem there).

Also, note that `TestSqliteFileSystem` cannot be used with WAL databases as the
file system does not implement memory-mapped IO.
