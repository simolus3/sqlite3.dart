import 'dart:typed_data';

import '../../common.dart';
import '../session.dart';
import 'bindings.dart';

base class ChangesetIteratorImplementation implements CommonChangesetIterator {
  final RawSqliteBindings bindings;
  final RawChangesetIterator iterator;

  ChangesetIteratorImplementation(this.bindings, this.iterator);
}

base class SessionImplementation implements CommonSession {
  final RawSqliteBindings bindings;
  final RawSqliteSession session;

  SessionImplementation(this.bindings, this.session);

  @override
  void attach([String? name]) {
    final result = bindings.sqlite3session_attach(session, name);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not attach session');
    }
  }

  @override
  Uint8List changeset() {
    return bindings.sqlite3session_changeset(session);
  }

  @override
  Uint8List patchset() {
    return bindings.sqlite3session_patchset(session);
  }

  @override
  void delete() {
    bindings.sqlite3session_delete(session);
  }
}
