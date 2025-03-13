import 'dart:typed_data';

import '../../common.dart';
import '../session.dart';
import 'bindings.dart';

base class SessionImplementation implements CommonSession {
  final RawSqliteBindings bindings;
  final RawSqliteSession session;

  SessionImplementation(this.bindings, this.session);

  @override
  Uint8List changeset() {
    final result = session.sqlite3session_changeset();
    if (result.resultCode != SqlError.SQLITE_OK) {
      throw SqliteException(result.resultCode, 'Could not get changeset');
    }
    return result.result;
  }

  @override
  Uint8List patchset() {
    final result = session.sqlite3session_patchset();
    if (result.resultCode != SqlError.SQLITE_OK) {
      throw SqliteException(result.resultCode, 'Could not get patchset');
    }
    return result.result;
  }

  @override
  void close() {
    session.sqlite3session_delete();
  }

  @override
  void diff(String fromDb, String table) {
    final result = session.sqlite3session_diff(fromDb, table);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not diff');
    }
  }

  @override
  void enable() {
    final result = session.sqlite3session_enable(1);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not enable session');
    }
  }

  @override
  void disable() {
    final result = session.sqlite3session_enable(0);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not disable session');
    }
  }

  @override
  bool isEnabled() {
    return session.sqlite3session_enable(-1) == 1;
  }

  @override
  bool isIndirect() {
    return session.sqlite3session_indirect(-1) == 1;
  }

  @override
  void setIndirect(bool indirect) {
    final result = session.sqlite3session_indirect(indirect ? 1 : 0);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not set indirect');
    }
  }

  @override
  bool isEmpty() {
    return session.sqlite3session_isempty() == 1;
  }

  @override
  void attach([String? table]) {
    final result = session.sqlite3session_attach(table);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not attach');
    }
  }
}
