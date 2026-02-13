import 'dart:ffi';

import 'package:meta/meta.dart';

import '../constants.dart';
import '../exception.dart';
import '../implementation/bindings.dart';
import '../implementation/database.dart';
import '../implementation/exception.dart';
import '../implementation/sqlite3.dart';
import '../implementation/statement.dart';
import '../sqlite3.dart';
import 'api.dart';
import 'bindings.dart';
import 'libsqlite3.g.dart' as libsqlite3;
import 'memory.dart';

final class FfiSqlite3 extends Sqlite3Implementation implements Sqlite3 {
  const FfiSqlite3() : super(ffiBindings);

  @override
  Database open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  }) {
    return super.open(filename, vfs: vfs, mode: mode, uri: uri, mutex: mutex)
        as Database;
  }

  @override
  FfiDatabaseImplementation openInMemory({String? vfs}) {
    return super.openInMemory(vfs: vfs) as FfiDatabaseImplementation;
  }

  @override
  Database wrapDatabase(RawSqliteDatabase rawDb) {
    return FfiDatabaseImplementation(rawDb as FfiDatabase);
  }

  @override
  Database copyIntoMemory(Database restoreFrom) {
    return openInMemory()..restore(restoreFrom);
  }

  @override
  void ensureExtensionLoaded(SqliteExtension extension) {
    initialize();

    final entrypoint = (extension as SqliteExtensionImpl)._resolveEntrypoint;
    final functionPtr = entrypoint();

    final result = libsqlite3.sqlite3_auto_extension(functionPtr);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(
        extendedResultCode: result,
        message: 'Could not load extension',
      );
    }
  }

  @override
  Database fromPointer(Pointer<void> database) {
    return wrapDatabase(FfiDatabase(database.cast()));
  }

  @override
  bool usedCompileOption(String name) {
    return ffiBindings.sqlite3_compileoption_used(name) != 0;
  }

  @override
  Iterable<String> get compileOptions sync* {
    var i = 0;
    while (true) {
      final option = ffiBindings.sqlite3_compileoption_get(i);
      if (option == null) {
        return;
      }

      yield option;
    }
  }
}

class SqliteExtensionImpl implements SqliteExtension {
  /// The internal function resolving the function pointer to pass to
  /// `sqlite3_auto_extension`.
  final Pointer<Void> Function() _resolveEntrypoint;

  SqliteExtensionImpl(this._resolveEntrypoint);
}

final class FfiDatabaseImplementation extends DatabaseImplementation
    implements Database {
  final FfiDatabase ffiDatabase;

  FfiDatabaseImplementation(this.ffiDatabase) : super(ffiBindings, ffiDatabase);

  @override
  FfiStatementImplementation wrapStatement(
    String sql,
    RawSqliteStatement stmt,
  ) {
    return FfiStatementImplementation(sql, this, stmt as FfiStatement);
  }

  @override
  Stream<double> backup(Database toDatabase, {int nPage = 5}) {
    if (isInMemory) {
      _loadOrSaveInMemoryDatabase(toDatabase, true);
      return const Stream.empty();
    } else {
      return _backupDatabase(toDatabase, nPage);
    }
  }

  @override
  Pointer<void> get handle => ffiDatabase.db;

  @override
  Pointer<void> leak() {
    ffiDatabase.detachFinalizer();
    return handle;
  }

  @override
  PreparedStatement prepare(
    String sql, {
    bool persistent = false,
    bool vtab = true,
    bool checkNoTail = false,
  }) {
    return super.prepare(
          sql,
          persistent: persistent,
          vtab: vtab,
          checkNoTail: checkNoTail,
        )
        as PreparedStatement;
  }

  @override
  List<PreparedStatement> prepareMultiple(
    String sql, {
    bool persistent = false,
    bool vtab = true,
  }) {
    return super
        .prepareMultiple(sql, persistent: persistent, vtab: vtab)
        .cast<PreparedStatement>();
  }

  /// check if this is a in-memory database
  @visibleForTesting
  bool get isInMemory {
    final zDbName = Utf8Utils.allocateZeroTerminated('main');
    final pFileName = libsqlite3.sqlite3_db_filename(ffiDatabase.db, zDbName);

    zDbName.free();

    return pFileName.isNullPointer || pFileName.readString().isEmpty;
  }

  /// Ported from https://www.sqlite.org/backup.html Example 1
  void _loadOrSaveInMemoryDatabase(Database other, bool isSave) {
    final fromDatabase = isSave ? this : other;
    final toDatabase = isSave ? other : this;

    final zDestDb = Utf8Utils.allocateZeroTerminated('main');
    final zSrcDb = Utf8Utils.allocateZeroTerminated('main');

    final pBackup = libsqlite3.sqlite3_backup_init(
      toDatabase.handle.cast(),
      zDestDb,
      fromDatabase.handle.cast(),
      zSrcDb,
    );

    if (!pBackup.isNullPointer) {
      libsqlite3.sqlite3_backup_step(pBackup, -1);
      libsqlite3.sqlite3_backup_finish(pBackup);
    }

    final extendedErrorCode = libsqlite3.sqlite3_extended_errcode(
      toDatabase.handle.cast(),
    );
    final errorCode = extendedErrorCode & 0xFF;

    zDestDb.free();
    zSrcDb.free();

    if (errorCode != SqlError.SQLITE_OK) {
      if (errorCode != SqlError.SQLITE_OK) {
        throw createExceptionFromExtendedCode(
          bindings,
          database,
          errorCode,
          extendedErrorCode,
        );
      }
    }
  }

  /// Ported from https://www.sqlite.org/backup.html Example 2
  Stream<double> _backupDatabase(Database toDatabase, int nPage) async* {
    final zDestDb = Utf8Utils.allocateZeroTerminated('main');
    final zSrcDb = Utf8Utils.allocateZeroTerminated('main');

    final pBackup = libsqlite3.sqlite3_backup_init(
      toDatabase.handle.cast(),
      zDestDb,
      ffiDatabase.db,
      zSrcDb,
    );

    int returnCode;
    if (!pBackup.isNullPointer) {
      do {
        returnCode = libsqlite3.sqlite3_backup_step(pBackup, nPage);

        final remaining = libsqlite3.sqlite3_backup_remaining(pBackup);
        final count = libsqlite3.sqlite3_backup_pagecount(pBackup);

        yield (count - remaining) / count;

        if (returnCode == SqlError.SQLITE_OK ||
            returnCode == SqlError.SQLITE_BUSY ||
            returnCode == SqlError.SQLITE_LOCKED) {
          //Give other threads the chance to work with the database
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      } while (returnCode == SqlError.SQLITE_OK ||
          returnCode == SqlError.SQLITE_BUSY ||
          returnCode == SqlError.SQLITE_LOCKED);

      libsqlite3.sqlite3_backup_finish(pBackup);
    }

    final extendedErrorCode = libsqlite3.sqlite3_extended_errcode(
      toDatabase.handle.cast(),
    );
    final errorCode = extendedErrorCode & 0xFF;

    zDestDb.free();
    zSrcDb.free();

    if (errorCode != SqlError.SQLITE_OK) {
      throw createExceptionFromExtendedCode(
        bindings,
        database,
        errorCode,
        extendedErrorCode,
      );
    }
  }

  @internal
  void restore(Database fromDatabase) {
    if (!isInMemory) {
      throw ArgumentError(
        'Restoring is only available for in-memory databases',
      );
    }

    _loadOrSaveInMemoryDatabase(fromDatabase, false);
  }
}

final class FfiStatementImplementation extends StatementImplementation
    implements PreparedStatement {
  final FfiStatement ffiStatement;

  FfiStatementImplementation(
    String sql,
    FfiDatabaseImplementation db,
    this.ffiStatement,
  ) : super(sql, db, ffiStatement);

  @override
  Pointer<void> get handle => ffiStatement.stmt;
}
