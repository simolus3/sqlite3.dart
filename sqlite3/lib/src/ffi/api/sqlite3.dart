import '../../../open.dart';
import '../../common/sqlite3.dart';
import '../ffi.dart';
import '../impl/implementation.dart';
import 'database.dart';

Sqlite3? _sqlite3;

/// Provides access to `sqlite3` functions, such as opening new databases.
Sqlite3 get sqlite3 {
  return _sqlite3 ??= Sqlite3._(open.openSqlite());
}

/// Provides access to `sqlite3` functions, such as opening new databases.
class Sqlite3 implements CommmonSqlite3 {
  final BindingsWithLibrary _library;

  Bindings get _bindings => _library.bindings;

  /// Loads `sqlite3` bindings by looking up functions in the [library].
  ///
  /// If application-defined functions are used, there shouldn't be multiple
  /// [Sqlite3] objects with a different underlying [library].
  Sqlite3._(DynamicLibrary library) : _library = BindingsWithLibrary(library);

  /// The version of the sqlite3 library in used.
  @override
  Version get version {
    final libVersion = _bindings.sqlite3_libversion().readString();
    final sourceId = _bindings.sqlite3_sourceid().readString();
    final versionNumber = _bindings.sqlite3_libversion_number();

    return Version(libVersion, sourceId, versionNumber);
  }

  @override
  Database open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  }) {
    return DatabaseImpl.open(
      _library,
      filename,
      vfs: vfs,
      mode: mode,
      uri: uri,
      mutex: mutex,
    );
  }

  /// Creates a [Database] from an opened sqlite3 database connection.
  ///
  /// The [database] must be a pointer towards an open sqlite3 database
  /// connection [handle](https://www.sqlite.org/c3ref/sqlite3.html).
  Database fromPointer(Pointer<void> database) {
    return DatabaseImpl(_library, database.cast());
  }

  @override
  Database openInMemory() {
    return DatabaseImpl.open(_library, ':memory:');
  }

  /// Opens a new in-memory database and copies another database into it
  /// https://www.sqlite.org/c3ref/backup_finish.html
  Database copyIntoMemory(Database restoreFrom) {
    return (openInMemory() as DatabaseImpl)..restore(restoreFrom);
  }

  @override
  String? get tempDirectory {
    final charPtr = _bindings.sqlite3_temp_directory;
    if (charPtr.isNullPointer) {
      return null;
    } else {
      return charPtr.readString();
    }
  }

  @override
  set tempDirectory(String? value) {
    if (value == null) {
      _bindings.sqlite3_temp_directory = nullPtr();
    } else {
      _bindings.sqlite3_temp_directory = allocateZeroTerminated(value);
    }
  }
}
