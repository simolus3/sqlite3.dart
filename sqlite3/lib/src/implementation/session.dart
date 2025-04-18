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

  bool _deleted = false;

  SessionImplementation(this.bindings, this.session);

  static SessionImplementation createSession(
      RawSqliteBindings bindings, RawSqliteDatabase db, String name) {
    final result = bindings
        .sqlite3session_create(db, name)
        .okOrThrowOutsideOfDatabase(bindings);

    return SessionImplementation(bindings, result);
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
  bool get enabled => session.sqlite3session_enable(-1) == 1;

  @override
  set enabled(bool enabled) {
    final result = session.sqlite3session_enable(enabled ? 1 : 0);
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }

  @override
  bool get isIndirect => session.sqlite3session_indirect(-1) == 1;

  @override
  set isIndirect(bool isIndirect) {
    final result = session.sqlite3session_enable(isIndirect ? 1 : 0);
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }

  @override
  bool get isEmpty => session.sqlite3session_isempty() != 0;

  @override
  bool get isNotEmpty => !isEmpty;

  @override
  void attach([String? table]) {
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
      null => null,
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
  operator -() {
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

      final oldColumns = List.generate(
        op.columnCount,
        (i) => raw
            .sqlite3changeset_old(i)
            .okOrThrowOutsideOfDatabase(bindings)
            .read(),
      );
      final newColumns = List.generate(
        op.columnCount,
        (i) => raw
            .sqlite3changeset_new(i)
            .okOrThrowOutsideOfDatabase(bindings)
            .read(),
      );
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

    final result = raw.sqlite3changeset_finalize();
    _isFinalized = true;
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }
  }
}
