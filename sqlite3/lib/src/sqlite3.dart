import 'database.dart';
import 'vfs.dart';

/// Provides access to `sqlite3` functions, such as opening new databases.
abstract interface class CommonSqlite3 {
  /// The version of the sqlite3 library in used.
  Version get version;

  /// Opens a database file.
  ///
  /// The [vfs] option can be used to set the appropriate virtual file system
  /// implementation. When null, the default file system will be used.
  ///
  /// If [uri] is enabled (defaults to `false`), the [filename] will be
  /// interpreted as an uri as according to https://www.sqlite.org/uri.html.
  ///
  /// If the [mutex] parameter is set to true, the `SQLITE_OPEN_FULLMUTEX` flag
  /// will be set. If it's set to false, `SQLITE_OPEN_NOMUTEX` will be enabled.
  /// By default, neither parameter will be set.
  CommonDatabase open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  });

  /// Opens an in-memory database.
  ///
  /// The [vfs] option can be used to set the appropriate virtual file system
  /// implementation. When null, the default file system will be used.
  CommonDatabase openInMemory({String? vfs});

  /// Accesses the `sqlite3_temp_directory` variable.
  ///
  /// Note that this operation might not be safe if a database connection is
  /// being used at the same time in different isolates.
  ///
  /// See also: https://www.sqlite.org/c3ref/temp_directory.html
  String? tempDirectory;

  /// Registers a custom virtual file system used by this sqlite3 instance to
  /// emulate I/O functionality that is not supported through WASM directly.
  ///
  /// Implementing a suitable [VirtualFileSystem] is a complex task. Users of
  /// this package on the web should consider using a package that calls this
  /// method for them (like `drift` or `sqflite_common_ffi_web`).
  /// For more information on how to implement this, see the readme of the
  /// `sqlite3` package for details.
  void registerVirtualFileSystem(VirtualFileSystem vfs,
      {bool makeDefault = false});

  /// Unregisters a virtual file system implementation that has been registered
  /// with [registerVirtualFileSystem].
  ///
  /// sqlite3 is not clear about what happens when this method is called with
  /// the file system being in used. Thus, this method should be used with care.
  void unregisterVirtualFileSystem(VirtualFileSystem vfs);
}

/// Version information about the sqlite3 library in use.
final class Version {
  /// A textual description of this sqlite version, such as '3.32.2'.
  final String libVersion;

  /// Detailed information about the source code of this sqlite build, which
  /// contains the Date of the latest change and a commit hash.
  final String sourceId;

  /// A numerical representation of [libVersion], such as `3032002`.
  final int versionNumber;

  /// Construct a version from the individual components.
  Version(this.libVersion, this.sourceId, this.versionNumber);

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
