import 'dart:typed_data';

// TODO: Match Node.js API

/// A Session tracks database changes made by a Conn.
//
/// It is used to build changesets.
///
/// Equivalent to the sqlite3_session* C object.
abstract interface class CommonSession {
  /// Changeset generates a changeset from a session.
  ///
  /// https://www.sqlite.org/session/sqlite3session_changeset.html
  Uint8List changeset();

  /// Patchset generates a patchset from a session.
  ///
  /// https://www.sqlite.org/session/sqlite3session_patchset.html
  Uint8List patchset();

  /// Delete deletes a Session object.
  ///
  /// https://www.sqlite.org/session/sqlite3session_delete.html
  void close();

  /// https://www.sqlite.org/session/sqlite3session_attach.html
  void attach([String? table]);

  /// Diff appends the difference between two tables (srcDB and the session DB) to the session.
  /// The two tables must have the same name and schema.
  /// https://www.sqlite.org/session/sqlite3session_diff.html
  void diff(String fromDb, String table);

  /// Enable enables recording of changes by a Session.
  /// New Sessions start enabled.
  ///
  /// https://www.sqlite.org/session/sqlite3session_enable.html
  void enable();

  /// Disable disables recording of changes by a Session.
  ///
  /// https://www.sqlite.org/session/sqlite3session_enable.html
  void disable();

  /// IsEnabled queries if the session is currently enabled.
  /// https://www.sqlite.org/session/sqlite3session_enable.html
  bool isEnabled();

  /// https://sqlite.org/session/sqlite3session_indirect.html
  bool isIndirect();

  /// https://sqlite.org/session/sqlite3session_indirect.html
  void setIndirect(bool indirect);

  /// https://sqlite.org/session/sqlite3session_isempty.html
  bool isEmpty();
}
