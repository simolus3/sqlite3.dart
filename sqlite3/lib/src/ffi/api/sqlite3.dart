import '../../../common.dart';
import '../../../open.dart';
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

  /// Loads an extensions through the `sqlite3_auto_extension` mechanism.
  ///
  /// For a more in-depth discussion, including links to an example, see the
  /// documentation for [SqliteExtension].
  void ensureExtensionLoaded(SqliteExtension extension) {
    final functionPtr = extension._resolveEntrypoint(_library.library);

    final result = _bindings.sqlite3_auto_extension(functionPtr);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not load extension');
    }
  }
}

typedef _ResolveEntrypoint = Pointer<Void> Function(DynamicLibrary);

/// Information used to load an extension through `sqlite3_auto_extension`,
/// exposed by [Sqlite3.ensureExtensionLoaded].
///
/// Note that this feature is __not__ a direct wrapper around sqlite3's dynamic
/// extension loading mechanism. In sqlite3 builds created through
/// `sqlite3_flutter_libs`, dynamic extensions are omitted from sqlite3 due to
/// security concerns.
///
/// However, if you want to manually load extensions, you can do that with a
/// [SqliteExtension] where the entrypoint is already known. This puts the
/// responsibility of dynamically loading code onto you.
///
/// For an example of how to write and load extensions, see
///  - this C file: https://github.com/simolus3/sqlite3.dart/blob/main/sqlite3/test/ffi/test_extension.c
///  - this Dart test loading it: https://github.com/simolus3/sqlite3.dart/blob/a9a379494c6b8d58a3c31cf04fe16e83b49130f1/sqlite3/test/ffi/sqlite3_test.dart#L35
class SqliteExtension {
  /// The internal function resolving the function pointer to pass to
  /// `sqlite3_auto_extension`.
  final _ResolveEntrypoint _resolveEntrypoint;

  /// A sqlite extension having the given [extensionEntrypoint] as a function
  /// pointer.
  ///
  /// For the exact signature of [extensionEntrypoint], see
  /// [sqlite3_auto_extension](https://www.sqlite.org/c3ref/auto_extension.html).
  factory SqliteExtension(Pointer<Void> extensionEntrypoint) {
    return SqliteExtension._((_) => extensionEntrypoint);
  }

  SqliteExtension._(this._resolveEntrypoint);

  /// A sqlite extension from another library with a given symbol as an
  /// entrypoint.
  factory SqliteExtension.inLibrary(DynamicLibrary library, String symbol) {
    return SqliteExtension._((_) => library.lookup(symbol));
  }

  /// A sqlite extension assumed to be statically linked into the sqlite3
  /// library loaded by this package.
  ///
  /// In most sqlite3 distributions, including the one from `sqlite3_flutter_libs`,
  /// no extensions are available this way.
  ///
  /// One example where an extension would be available is if you added a
  /// native dependency on the `sqlite3/spellfix1` pod on iOS or macOS. On those
  /// platforms, you could then load the  [spellfix](https://www.sqlite.org/spellfix1.html)
  /// extension with `SqliteExtension.staticallyLinked('sqlite3_spellfix_init')`.
  factory SqliteExtension.staticallyLinked(String symbol) {
    return SqliteExtension._((library) => library.lookup(symbol));
  }
}
