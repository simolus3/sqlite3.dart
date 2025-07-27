import 'dart:typed_data';

import '../constants.dart';
import '../database.dart';
import '../session.dart';
import 'bindings.dart';
import 'database.dart';
import 'exception.dart';
import 'utils.dart';

final class SessionImplementation implements Session {
  final RawSqliteBindings bindings;
  final RawSqliteSession session;
  final FinalizableDatabase database;

  bool _deleted = false;

  SessionImplementation(this.bindings, this.session, this.database) {
    database.dartCleanup.add(delete);
  }

  static SessionImplementation createSession(
      DatabaseImplementation db, String name) {
    final bindings = db.bindings;
    final result = bindings.sqlite3session_create(db.database, name);
    return SessionImplementation(bindings, result, db.finalizable);
  }

  void _checkNotDeleted() {
    if (_deleted) {
      throw StateError('This session has already been deleted');
    }
  }

  @override
  Changeset changeset() {
    _checkNotDeleted();
    final bytes = session.sqlite3session_changeset();
    return ChangesetImplementation(bytes, bindings);
  }

  @override
  Patchset patchset() {
    _checkNotDeleted();
    final bytes = session.sqlite3session_patchset();
    return PatchsetImplementation(bytes, bindings);
  }

  @override
  void delete() {
    if (!_deleted) {
      _deleted = true;
      session.sqlite3session_delete();
      database.dartCleanup.remove(delete);
    }
  }

  @override
  void diff(String fromDb, String table) {
    final result = session.sqlite3session_diff(fromDb, table);
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }

  @override
  bool get enabled {
    _checkNotDeleted();
    return session.sqlite3session_enable(-1) == 1;
  }

  @override
  set enabled(bool enabled) {
    _checkNotDeleted();
    final result = session.sqlite3session_enable(enabled ? 1 : 0);
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }

  @override
  bool get isIndirect {
    _checkNotDeleted();
    return session.sqlite3session_indirect(-1) == 1;
  }

  @override
  set isIndirect(bool isIndirect) {
    _checkNotDeleted();
    final result = session.sqlite3session_enable(isIndirect ? 1 : 0);
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }

  @override
  bool get isEmpty {
    _checkNotDeleted();
    return session.sqlite3session_isempty() != 0;
  }

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  void attach([String? table]) {
    _checkNotDeleted();
    final result = session.sqlite3session_attach(table);
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }
}

final class PatchsetImplementation
    with Iterable<ChangesetOperation>
    implements Patchset {
  @override
  final Uint8List bytes;
  final RawSqliteBindings bindings;

  PatchsetImplementation(this.bytes, this.bindings);

  @override
  void applyTo(CommonDatabase database,
      [ApplyChangesetOptions options = const ApplyChangesetOptions()]) {
    final db = database as DatabaseImplementation;

    final filter = switch (options.filter) {
      null => null,
      final filter => (String table) {
          return filter(table) ? 1 : 0;
        }
    };

    final conflict = switch (options.onConflict) {
      null => (int _, RawChangesetIterator __) {
          return ApplyChangesetConflict.abort.flag;
        },
      final conflict => (int conflictKind, RawChangesetIterator it) {
          return conflict.flag;
        }
    };

    db.bindings.sqlite3changeset_apply(
      db.database,
      bytes,
      filter,
      conflict,
    );
  }

  @override
  ChangesetIterator get iterator {
    final raw = bindings.sqlite3changeset_start(bytes);
    return ChangesetIteratorImplementation(bindings, raw);
  }
}

final class ChangesetImplementation extends PatchsetImplementation
    implements Changeset {
  ChangesetImplementation(super.bytes, super.bindings);

  @override
  Changeset operator -() {
    final result = bindings.sqlite3changeset_invert(bytes);
    return ChangesetImplementation(result, bindings);
  }
}

final class ChangesetIteratorImplementation implements ChangesetIterator {
  final RawSqliteBindings bindings;
  final RawChangesetIterator raw;

  bool _isFinalized = false;

  @override
  late ChangesetOperation current;

  ChangesetIteratorImplementation(this.bindings, this.raw);

  @override
  bool moveNext() {
    if (_isFinalized) {
      return false;
    }

    final result = raw.sqlite3changeset_next();
    if (result == SqlError.SQLITE_ROW) {
      final op = raw.sqlite3changeset_op();
      final kind = SqliteUpdateKind.fromCode(op.operation)!;

      final oldColumns = kind != SqliteUpdateKind.insert
          ? List.generate(
              op.columnCount,
              (i) => raw
                  .sqlite3changeset_old(i)
                  .okOrThrowOutsideOfDatabase(bindings)
                  ?.read(),
            )
          : null;
      final newColumns = kind != SqliteUpdateKind.delete
          ? List.generate(
              op.columnCount,
              (i) => raw
                  .sqlite3changeset_new(i)
                  .okOrThrowOutsideOfDatabase(bindings)
                  ?.read(),
            )
          : null;
      current = ChangesetOperation(
        table: op.tableName,
        columnCount: op.columnCount,
        operation: kind,
        oldValues: oldColumns,
        newValues: newColumns,
      );

      return true;
    }

    finalize();
    return false;
  }

  @override
  void finalize() {
    if (_isFinalized) {
      return;
    }

    _isFinalized = true;
    final result = raw.sqlite3changeset_finalize();
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }
}
