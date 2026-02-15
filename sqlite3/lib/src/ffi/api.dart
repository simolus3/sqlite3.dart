import 'dart:ffi';

import '../database.dart';
import '../sqlite3.dart';
import '../statement.dart';
import 'libsqlite3.g.dart' as libsqlite3;
import 'implementation.dart';

/// Provides access to `sqlite3` functions, such as opening new databases.
///
/// {@category native}
const Sqlite3 sqlite3 = FfiSqlite3();

/// Provides access to `sqlite3` functions, such as opening new databases.
///
/// {@category native}
abstract interface class Sqlite3 implements CommonSqlite3 {
  @override
  Database open(
    String filename, {
    String? vfs,
    OpenMode mode = OpenMode.readWriteCreate,
    bool uri = false,
    bool? mutex,
  });

  /// Creates a [Database] from an opened sqlite3 database connection.
  ///
  /// The [database] must be a pointer towards an open sqlite3 database
  /// connection [handle](https://www.sqlite.org/c3ref/sqlite3.html).
  ///
  /// When [borrowed] is set (it defaults to `false`), the returned [Database]
  /// connection acts as a view of the underlying `sqlite3*` pointer. The
  /// library will not attach a native finalizer calling `sqlite3_close_v2`, and
  /// calling [Database.close] in it will only prevent further interactions from
  /// Dart.
  Database fromPointer(Pointer<void> database, {bool borrowed = false});

  @override
  Database openInMemory({String? vfs});

  /// Opens a new in-memory database and copies another database into it
  /// https://www.sqlite.org/c3ref/backup_finish.html
  Database copyIntoMemory(Database restoreFrom);

  /// Loads an extensions through the `sqlite3_auto_extension` mechanism.
  ///
  /// For a more in-depth discussion, including links to an example, see the
  /// documentation for [SqliteExtension].
  void ensureExtensionLoaded(SqliteExtension extension);

  /// Whether the option, specified by its name, was defined at compile-time.
  ///
  /// The `SQLITE_` prefix may be omitted from the option [name].
  ///
  /// See also: https://sqlite.org/c3ref/compileoption_get.html
  bool usedCompileOption(String name);

  /// An iterable over the list of options that were defined at compile time.
  ///
  /// See also: https://sqlite.org/c3ref/compileoption_get.html
  Iterable<String> get compileOptions;

  /// A function pointer to `sqlite3_close_v2`.
  ///
  /// This typically shouldn't be used directly since this library attaches
  /// native finalizers to databases by default, but can be used for custom
  /// connection management if necessary.
  ///
  /// See also: https://sqlite.org/c3ref/close.html
  static Pointer<NativeFunction<Int Function(Pointer<Void>)>>
  get sqliteCloseV2 => libsqlite3.addresses.sqlite3_close_v2.cast();
}

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
///  - Or, alternatively, this Flutter example: https://github.com/simolus3/sqlite3.dart/tree/main/sqlite3/example/custom_extension
///
/// {@category native}
abstract interface class SqliteExtension {
  /// A sqlite extension having the given [extensionEntrypoint] as a function
  /// pointer.
  ///
  /// For the exact signature of [extensionEntrypoint], see
  /// [sqlite3_auto_extension](https://www.sqlite.org/c3ref/auto_extension.html).
  factory SqliteExtension(Pointer<Void> extensionEntrypoint) {
    return SqliteExtensionImpl(() => extensionEntrypoint);
  }

  /// A sqlite extension from another library with a given symbol as an
  /// entrypoint.
  factory SqliteExtension.inLibrary(DynamicLibrary library, String symbol) {
    return SqliteExtensionImpl(() => library.lookup(symbol));
  }
}

/// An opened sqlite3 database with `dart:ffi`.
///
/// See [CommonDatabase] for the methods that are available on both the FFI and
/// the WebAssembly implementation.
///
/// {@category native}
abstract class Database extends CommonDatabase {
  /// The native database connection handle from sqlite.
  ///
  /// This returns a pointer towards the opaque sqlite3 structure as defined
  /// [here](https://www.sqlite.org/c3ref/sqlite3.html).
  ///
  /// Note that the connection is still owned by this Dart object, and will be
  /// closed once it becomes unreachable. In other words, the returned handle is
  /// a logical reference to this object.
  /// To transfer ownership of the connection out of this object, use [leak]
  /// instead.
  Pointer<void> get handle;

  /// Like [handle], this returns the native `sqlite3*` pointer wrapped by this
  /// instance.
  ///
  /// Additionally, this also detaches native finalizers that would close the
  /// connection once this object becomes unreachable.
  ///
  /// This is an advanced and low-level API that can be used to transfer
  /// ownership of connections originally opened in Dart to native code.
  Pointer<void> leak();

  // override for more specific subtype
  @override
  PreparedStatement prepare(
    String sql, {
    bool persistent = false,
    bool vtab = true,
    bool checkNoTail = false,
  });

  @override
  List<PreparedStatement> prepareMultiple(
    String sql, {
    bool persistent = false,
    bool vtab = true,
  });

  /// Create a backup of the current database (this) into another database
  /// ([toDatabase]) on memory or disk.
  ///
  /// The returned stream returns a rough estimate on the progress of the
  /// backup, as a fraction between `0` and `1`. No progress is reported if
  /// either this or [toDatabase] is an in-memory database.
  ///
  /// To simply await the backup operation as a future, call [Stream.drain] on
  /// the returned stream.
  ///
  /// [nPage] is the number of pages backed-up in each backup step.
  /// A larger value increase speed of backup, but will cause other connections to wait
  /// longer to aquire locks on the source and destination databases.  A value of -1
  /// can be used to backup the entire database in a single step.
  /// See https://www.sqlite.org/c3ref/backup_finish.html#sqlite3backupstep for details.
  ///
  /// See https://www.sqlite.org/c3ref/backup_finish.html
  Stream<double> backup(Database toDatabase, {int nPage = 5});
}

/// A prepared statement.
///
/// {@category native}
abstract class PreparedStatement implements CommonPreparedStatement {
  /// The underlying `sqlite3_stmt` pointer.
  ///
  /// Obtains the raw [statement](https://www.sqlite.org/c3ref/stmt.html) from
  /// the sqlite3 C-api that this [PreparedStatement] wraps.
  Pointer<void> get handle;
}
