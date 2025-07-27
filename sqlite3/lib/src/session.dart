import 'dart:typed_data';

import 'database.dart';
import 'implementation/database.dart';
import 'implementation/session.dart';
import 'implementation/sqlite3.dart';
import 'sqlite3.dart';

/// A Session tracks database changes made by a Conn.
//
/// It is used to build changesets.
///
/// Equivalent to the sqlite3_session* C object.
///
/// {@category common}
abstract interface class Session {
  factory Session(CommonDatabase database, {String name = 'main'}) {
    final asImpl = database as DatabaseImplementation;
    return SessionImplementation.createSession(asImpl, name);
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

/// A patchset obtained from a byte sequence or an active [Session].
///
/// Unlike [Changeset]s, patchsets don't store values for deletions (apart from
/// the primary key) and don't keep original values for `UPDATE` records.
///
/// {@category common}
abstract interface class Patchset implements Iterable<ChangesetOperation> {
  /// The binary representation of this patchset or changeset.
  Uint8List get bytes;

  @override
  ChangesetIterator get iterator;

  /// Creates a patch set from the underlying serialized byte representation.
  factory Patchset.fromBytes(Uint8List bytes, CommonSqlite3 bindings) {
    return PatchsetImplementation(
        bytes, (bindings as Sqlite3Implementation).bindings);
  }

  /// Applies this changeset or patchset to the [database].
  void applyTo(
    CommonDatabase database, [
    ApplyChangesetOptions options = const ApplyChangesetOptions(),
  ]);
}

/// A changeset, representing changes made while a [Session] is active.
///
/// {@category common}
abstract interface class Changeset implements Patchset {
  /// Creates a changeset from the underlying serialized byte representation.
  factory Changeset.fromBytes(Uint8List bytes, CommonSqlite3 bindings) {
    return ChangesetImplementation(
        bytes, (bindings as Sqlite3Implementation).bindings);
  }

  /// Inverts this changeset.
  Changeset operator -();
}

/// A recorded operation on a changeset.
///
/// {@category common}
final class ChangesetOperation {
  /// Name of the table affected by the operation.
  final String table;

  /// The amount of columns in the table, which equals the [List.length] of
  /// [oldValues] and [newValues].
  final int columnCount;

  /// The type of update made.
  final SqliteUpdateKind operation;

  /// If [operation] is not [SqliteUpdateKind.insert], a list of values in the
  /// row before the operation.
  final List<Object?>? oldValues;

  /// If [operation] is not [SqliteUpdateKind.delete], a list of values in the
  /// row after the operation.
  final List<Object?>? newValues;

  ChangesetOperation({
    required this.table,
    required this.columnCount,
    required this.operation,
    required this.oldValues,
    required this.newValues,
  });

  @override
  String toString() {
    return 'ChangesetOperation: $operation on $table. old: $oldValues, new: $newValues';
  }
}

/// An [Iterator] through a [Changeset] or [Patchset].
abstract interface class ChangesetIterator
    implements Iterator<ChangesetOperation> {
  /// Aborts this iterator and frees internal resources.
  ///
  /// This is also called automatically when [moveNext] returns false, but needs
  /// to be called manually if the iterator is not completed.
  void finalize();
}

class ApplyChangesetOptions {
  /// An optional filter to only apply changes on some tables.
  ///
  /// When set, only operators on tables for which this function returns true
  /// are applied.
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
