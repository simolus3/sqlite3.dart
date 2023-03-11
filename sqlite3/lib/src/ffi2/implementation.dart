import 'dart:ffi';

import '../implementation/bindings.dart';
import '../implementation/database.dart';
import '../implementation/sqlite3.dart';
import '../implementation/statement.dart';
import '../sqlite3.dart';
import 'api.dart';
import 'bindings.dart';

class FfiSqlite3 extends Sqlite3Implementation implements Sqlite3 {
  final FfiBindings ffiBindings;

  factory FfiSqlite3(DynamicLibrary library) {
    return FfiSqlite3._(FfiBindings(BindingsWithLibrary(library)));
  }

  FfiSqlite3._(this.ffiBindings) : super(ffiBindings);

  @override
  Database open(String filename,
      {String? vfs,
      OpenMode mode = OpenMode.readWriteCreate,
      bool uri = false,
      bool? mutex}) {
    return super.open(filename, vfs: vfs, mode: mode, uri: uri, mutex: mutex)
        as Database;
  }

  @override
  Database openInMemory() {
    return super.openInMemory() as Database;
  }

  @override
  Database wrapDatabase(RawSqliteDatabase rawDb) {
    return FfiDatabaseImplementation(bindings, rawDb as FfiDatabase);
  }

  @override
  Database copyIntoMemory(Database restoreFrom) {
    // TODO: implement copyIntoMemory
    throw UnimplementedError();
  }

  @override
  void ensureExtensionLoaded(SqliteExtension extension) {
    // TODO: implement ensureExtensionLoaded
  }

  @override
  Database fromPointer(Pointer<void> database) {
    return wrapDatabase(FfiDatabase(ffiBindings.bindings, database.cast()));
  }
}

class FfiDatabaseImplementation extends DatabaseImplementation
    implements Database {
  final FfiDatabase ffiDatabase;

  FfiDatabaseImplementation(RawSqliteBindings bindings, this.ffiDatabase)
      : super(bindings, ffiDatabase);

  @override
  FfiStatementImplementation wrapStatement(
      String sql, RawSqliteStatement stmt) {
    return FfiStatementImplementation(sql, this, stmt as FfiStatement);
  }

  @override
  Stream<double> backup(Database toDatabase) {
    throw UnimplementedError();
  }

  @override
  Pointer<void> get handle => throw UnimplementedError();

  @override
  PreparedStatement prepare(String sql,
      {bool persistent = false, bool vtab = true, bool checkNoTail = false}) {
    return super.prepare(sql,
        persistent: persistent,
        vtab: vtab,
        checkNoTail: checkNoTail) as PreparedStatement;
  }

  @override
  List<PreparedStatement> prepareMultiple(String sql,
      {bool persistent = false, bool vtab = true}) {
    return super
        .prepareMultiple(sql, persistent: persistent, vtab: vtab)
        .cast<PreparedStatement>();
  }
}

class FfiStatementImplementation extends StatementImplementation
    implements PreparedStatement {
  final FfiStatement ffiStatement;

  FfiStatementImplementation(
      String sql, FfiDatabaseImplementation db, this.ffiStatement)
      : super(sql, db, ffiStatement);

  @override
  Pointer<void> get handle => ffiStatement.stmt;
}
