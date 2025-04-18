import 'dart:typed_data';

import 'database.dart';
import 'implementation/database.dart';
import 'implementation/session.dart';

/// A Session tracks database changes made by a Conn.
//
/// It is used to build changesets.
///
/// Equivalent to the sqlite3_session* C object.
abstract interface class Session {
  factory Session(CommonDatabase database, {String name = 'main'}) {
    final asImpl = database as DatabaseImplementation;

    return SessionImplementation.createSession(
        asImpl.bindings, asImpl.database, name);
  }

  /// Changeset generates a changeset from a session.
  ///
  /// https://www.sqlite.org/session/sqlite3session_changeset.html
  Changeset changeset();

  /// Patchset generates a patchset from a session.
  ///
  /// https://www.sqlite.org/session/sqlite3session_patchset.html
  Patchset patchset();

  /// Delete deletes a Session object.
  ///
  /// https://www.sqlite.org/session/sqlite3session_delete.html
  void delete();

  /// https://www.sqlite.org/session/sqlite3session_attach.html
  void attach([String? table]);

  /// Diff appends the difference between two tables (srcDB and the session DB) to the session.
  /// The two tables must have the same name and schema.
  /// https://www.sqlite.org/session/sqlite3session_diff.html
  void diff(String fromDb, String table);

  /// IsEnabled queries if the session is currently enabled.
  /// https://www.sqlite.org/session/sqlite3session_enable.html
  abstract bool enabled;

  /// https://sqlite.org/session/sqlite3session_indirect.html
  abstract bool isIndirect;

  /// https://sqlite.org/session/sqlite3session_isempty.html
  bool get isEmpty;

  bool get isNotEmpty;
}

abstract interface class Patchset implements Iterable<ChangesetOperation> {
  /// The binary representation of this patchset or changeset.
  Uint8List get bytes;

  void applyTo(
    CommonDatabase database, [
    ApplyChangesetOptions options = const ApplyChangesetOptions(),
  ]);

  @override
  ChangesetIterator get iterator;
}

abstract interface class Changeset implements Patchset {
  operator -();
}

final class ChangesetOperation {
  final String table;
  final int columnCount;
  final SqliteUpdateKind operation;

  final List<Object?> oldValues;
  final List<Object?> newValues;

  ChangesetOperation({
    required this.table,
    required this.columnCount,
    required this.operation,
    required this.oldValues,
    required this.newValues,
  });
}

abstract interface class ChangesetIterator
    implements Iterator<ChangesetOperation> {
  void finalize();
}

class ApplyChangesetOptions {
  /// Skip changes that, when targeted table name is supplied to this function, return a truthy value.
  /// By default, all changes are attempted.
  final bool Function(String tableName)? filter;

  /// Determines how conflicts are handled. **Default**: `SQLITE_CHANGESET_ABORT`.
  final ApplyChangesetConflict? onConflict;

  const ApplyChangesetOptions({this.filter, this.onConflict});
}

// #define SQLITE_CHANGESET_OMIT       0
// #define SQLITE_CHANGESET_REPLACE    1
// #define SQLITE_CHANGESET_ABORT      2
enum ApplyChangesetConflict {
  /// Abort the changeset application.
  abort(2),

  /// Replace the conflicting row.
  replace(1),

  /// Omit the current change.
  omit(0);

  final int flag;
  const ApplyChangesetConflict(this.flag);

  static ApplyChangesetConflict parse(int flag) {
    return ApplyChangesetConflict.values.firstWhere((e) => e.flag == flag);
  }
}
