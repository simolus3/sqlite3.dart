import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3/src/ffi/ffi.dart';
import 'package:sqlite3/src/impl/implementation.dart';

/// Provides access to `sqlite3` functions, such as opening new databases.
Sqlite3 sqlite3 = Sqlite3._(open.openSqlite());

/// Provides access to `sqlite3` functions, such as opening new databases.
class Sqlite3 {
  final Bindings _bindings;

  /// Loads `sqlite3` bindings by looking up functions in the [library].
  ///
  /// If application-defined functions are used, there shouldn't be multiple
  /// [Sqlite3] objects with a different underlying [library].
  Sqlite3._(DynamicLibrary library) : _bindings = Bindings(library);

  /// The version of the sqlite3 library in used.
  Version get version {
    final libVersion = _bindings.sqlite3_libversion().readString();
    final sourceId = _bindings.sqlite3_sourceid().readString();
    final versionNumber = _bindings.sqlite3_libversion_number();

    return Version._(libVersion, sourceId, versionNumber);
  }

  /// Opens a database file.
  ///
  /// The [vfs] option can be used to set the appropriate virtual file system
  /// implementation. When null, the default file system will be used.
  ///
  /// If [uri] is enabled (defaults to `false`), the [filename] will be
  /// interpreted as an uri as according to https://www.sqlite.org/uri.html.
  Database open(
    String filename, {
    String /*?*/ vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
  }) {
    return DatabaseImpl.open(
      _bindings,
      filename,
      vfs: vfs,
      mode: mode,
      uri: uri,
    );
  }

  /// Creates a [Database] from an opened sqlite3 database connection.
  ///
  /// The [database] must be a pointer towards an open sqlite3 database
  /// connection [handle](https://www.sqlite.org/c3ref/sqlite3.html).
  Database fromPointer(Pointer<void> database) {
    return DatabaseImpl(_bindings, database.cast());
  }

  /// Opens an in-memory database.
  Database openInMemory() {
    return DatabaseImpl.open(_bindings, ':memory:');
  }
}

/// Version information about the sqlite3 library in use.
class Version {
  /// A textual description of this sqlite version, such as '3.32.2'.
  final String libVersion;

  /// Detailed information about the source code of this sqlite build, which
  /// contains the Date of the latest change and a commit hash.
  final String sourceId;

  /// A numerical representation of [libVersion], such as `3032002`.
  final int versionNumber;

  Version._(this.libVersion, this.sourceId, this.versionNumber);

  @override
  String toString() {
    return 'Version(libVersion: $libVersion, sourceId: $sourceId, '
        'number: $versionNumber)';
  }
}

/// Controls how databases should be opened by sqlite
enum OpenMode {
  /// The database is opened in read-only mode. If the database does not already
  /// exist, an error is returned.
  readOnly,

  /// The database is opened for reading and writing if possible, or reading
  /// only if the file is write protected by the operating system. In either
  /// case the database must already exist, otherwise an error is returned.
  readWrite,

  /// The database is opened for reading and writing, and is created if it does
  /// not already exist
  readWriteCreate,
}
