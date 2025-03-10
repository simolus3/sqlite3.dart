import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../constants.dart';
import '../database.dart';
import '../exception.dart';
import '../session.dart';
import '../sqlite3.dart';
import '../vfs.dart';
import 'bindings.dart';
import 'database.dart';
import 'exception.dart';

base class Sqlite3Implementation implements CommonSqlite3 {
  final RawSqliteBindings bindings;

  Sqlite3Implementation(this.bindings);

  @visibleForOverriding
  CommonDatabase wrapDatabase(RawSqliteDatabase rawDb) {
    return DatabaseImplementation(bindings, rawDb);
  }

  @override
  CommonSession createSession(CommonDatabase database, String name) {
    return database.createSession(name);
  }

  @override
  void sessionAttach(CommonSession session, String? name) {
    final instance = session as SessionImplementation;
    final rc = bindings.sqlite3session_attach(instance.session, name);
    if (rc != 0) {
      throw SqliteException(rc, 'Error returned by sqlite3_initialize');
    }
  }

  @override
  Uint8List sessionChangeset(CommonSession session) {
    final instance = session as SessionImplementation;
    return bindings.sqlite3session_changeset(instance.session);
  }

  @override
  Uint8List sessionPatchset(CommonSession session) {
    final instance = session as SessionImplementation;
    return bindings.sqlite3session_patchset(instance.session);
  }

  @override
  void sessionDelete(CommonSession session) {
    final instance = session as SessionImplementation;
    bindings.sqlite3session_delete(instance.session);
  }

  @override
  void sessionChangesetApply(
    CommonDatabase database,
    Uint8List changeset, {
    int Function(
      CommonDatabase ctx,
      String tableName,
    )? filter,
    ApplyChangesetRule Function(
      CommonDatabase ctx,
      ApplyChangesetConflict eConflict,
      CommonChangesetIterator iter,
    )? conflict,
  }) {
    final db = (database as DatabaseImplementation).database;

    int Function(RawSqliteDatabase, String)? _filter;
    int Function(RawSqliteDatabase, int, RawChangesetIterator)? _conflict;

    if (filter != null) {
      _filter = (db, table) => filter(database, table);
    }

    if (conflict != null) {
      _conflict = (db, conflictCode, iterator) {
        final conflictType = ApplyChangesetConflict.parse(conflictCode);
        final iteratorImpl =
            ChangesetIteratorImplementation(bindings, iterator);
        final result = conflict(database, conflictType, iteratorImpl);
        return result.raw;
      };
    }

    bindings.sqlite3changeset_apply(db, changeset, _filter, _conflict, db);
  }

  @override
  String? get tempDirectory => bindings.sqlite3_temp_directory;

  @override
  set tempDirectory(String? value) => bindings.sqlite3_temp_directory = value;

  void initialize() {
    final rc = bindings.sqlite3_initialize();
    if (rc != 0) {
      throw SqliteException(rc, 'Error returned by sqlite3_initialize');
    }
  }

  @override
  CommonDatabase open(String filename,
      {String? vfs,
      OpenMode mode = OpenMode.readWriteCreate,
      bool uri = false,
      bool? mutex}) {
    initialize();

    int flags;
    switch (mode) {
      case OpenMode.readOnly:
        flags = SqlFlag.SQLITE_OPEN_READONLY;
        break;
      case OpenMode.readWrite:
        flags = SqlFlag.SQLITE_OPEN_READWRITE;
        break;
      case OpenMode.readWriteCreate:
        flags = SqlFlag.SQLITE_OPEN_READWRITE | SqlFlag.SQLITE_OPEN_CREATE;
        break;
    }

    if (uri) {
      flags |= SqlFlag.SQLITE_OPEN_URI;
    }

    if (mutex != null) {
      flags |=
          mutex ? SqlFlag.SQLITE_OPEN_FULLMUTEX : SqlFlag.SQLITE_OPEN_NOMUTEX;
    }

    final result = bindings.sqlite3_open_v2(filename, flags, vfs);
    if (result.resultCode != SqlError.SQLITE_OK) {
      final exception = createExceptionRaw(
          bindings, result.result, result.resultCode,
          operation: 'opening the database');
      // Close the database after creating the exception, which needs to read
      // the extended error from the database.
      result.result.sqlite3_close_v2();
      throw exception;
    }

    return wrapDatabase(result.result..sqlite3_extended_result_codes(1));
  }

  @override
  CommonDatabase openInMemory({String? vfs}) {
    return open(':memory:', vfs: vfs);
  }

  @override
  void registerVirtualFileSystem(VirtualFileSystem vfs,
      {bool makeDefault = false}) {
    bindings.registerVirtualFileSystem(vfs, makeDefault ? 1 : 0);
  }

  @override
  void unregisterVirtualFileSystem(VirtualFileSystem vfs) {
    bindings.unregisterVirtualFileSystem(vfs);
  }

  @override
  Version get version {
    return Version(
      bindings.sqlite3_libversion(),
      bindings.sqlite3_sourceid(),
      bindings.sqlite3_libversion_number(),
    );
  }
}
