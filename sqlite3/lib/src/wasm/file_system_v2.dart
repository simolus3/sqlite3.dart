part of 'file_system.dart';

/// A file system storing whole files in an IndexedDB database.
///
/// As sqlite3's file system is synchronous and IndexedDB isn't, no guarantees
/// on durability can be made. Instead, file changes are written at some point
/// after the database is changed. However you can wait for changes manually
/// with [flush]
///
/// In the future, we may want to store individual blocks instead.

class IndexedDbFileSystemV2 implements FileSystem {
  final String _persistenceRoot;
  final String _objectName;
  final Database _database;
  final String dbName;
  final _InMemoryFileSystem _memory = _InMemoryFileSystem();

  bool _closed = false;
  Future<void>? _current;

  IndexedDbFileSystemV2._(
      this._persistenceRoot, this._database, this.dbName, this._objectName);

  /// Loads an IndexedDB file system that will consider files in
  /// [persistenceRoot].
  ///
  /// When one application needs to support different database files, putting
  /// them into different folders and setting the persistence root to ensure
  /// that one [IndexedDbFileSystem] will only see one of them decreases memory
  /// usage.
  ///
  /// [persistenceRoot] is prepended to file names at database level, so you
  /// have to use relative path in function parameter. Provided paths are
  /// normalized and resolved like in any operating system:
  /// /foo/bar/../foo -> /foo/foo
  /// //foo///bar/../foo/ -> /foo/foo
  ///
  /// The persistence root can be set to `/` to make all files available.
  /// Be careful not to use the same or nested [persistenceRoot] for different
  /// instances with the same database and object name. These can overwrite each
  /// other and undefined behavior can occur.
  ///
  /// With [dbName] you can set IndexedDB database name
  /// With [objectName] you can set file storage object key name
  static Future<IndexedDbFileSystemV2> init({
    String persistenceRoot = '/',
    String dbName = 'sqlite3_databases',
    String objectName = 'files',
  }) async {
    final openDatabase = (int? version) {
      // Not using window.indexedDB because we want to support workers too.
      return self.indexedDB!.open(
        dbName,
        version: version,
        onUpgradeNeeded: version == null
            ? null
            : (event) {
                final database = event.target.result as Database;
                database.createObjectStore(objectName);
              },
      );
    };

    // Check if a new objectName is used on existing database. Must run
    // upgrade in this case.
    // Because of a bug in DartVM, it can run into a deadlock when run parallel
    // access to the same database while upgrading
    // https://github.com/dart-lang/sdk/issues/48854
    var database = await openDatabase(null);
    if (!(database.objectStoreNames ?? []).contains(objectName)) {
      database.close();
      database = await openDatabase((database.version ?? 1) + 1);
    }

    final root = p.posix.normalize('/$persistenceRoot');
    final fs = IndexedDbFileSystemV2._(root, database, dbName, objectName);
    await fs._sync();
    return fs;
  }

  /// Returns all database
  /// Returns null if 'IndexedDB.databases()' function is not supported in the
  /// JS engine
  static Future<List<DatabaseName>?> databases() async {
    try {
      return await self.indexedDB!.databases();
    } on Exception catch (_) {
      return null;
    }
  }

  static Future<void> deleteDatabase(
      [String dbName = 'sqlite3_databases']) async {
    // The deadlock issue can cause problem here too
    // https://github.com/dart-lang/sdk/issues/48854
    await self.indexedDB!.deleteDatabase(dbName);
  }

  bool get isClosed => _closed;

  Future<void> close() async {
    if (!_closed) {
      await flush();
      _database.close();
      _memory.clear();
      _closed = true;
    }
  }

  void _checkClosed() {
    if (_closed) {
      throw FileSystemException(SqlError.SQLITE_IOERR, 'FileSystem closed');
    }
  }

  /// Flush and reload files from IndexedDB
  Future<void> sync() async {
    _checkClosed();
    await _mutex(() => _sync());
  }

  Future<void> _sync() async {
    final transaction = _database.transactionStore(_objectName, 'readonly');
    final files = transaction.objectStore(_objectName);
    _memory.clear();
    await for (final entry in files.openCursor(autoAdvance: true)) {
      final path = entry.primaryKey! as String;
      if (p.url.isWithin(_persistenceRoot, path)) {
        final object = await entry.value as Blob?;
        if (object == null) continue;

        _memory._files[_relativePath(path)] = await object.arrayBuffer();
      }
    }
  }

  String _normalize(String path) {
    if (path.endsWith('/') || path.endsWith('.')) {
      throw FileSystemException(
          SqlExtendedError.SQLITE_CANTOPEN_ISDIR, 'Path is a directory');
    }
    return p.posix.normalize('/${path}');
  }

  /// Returns the absolute path to IndexedDB
  String absolutePath(String path) {
    _checkClosed();
    return p.posix.normalize('/$_persistenceRoot/$path');
  }

  String _relativePath(String path) =>
      p.posix.normalize(path.replaceFirst(_persistenceRoot, '/'));

  Future<void> _mutex(Future<void> Function() body) async {
    await flush();
    try {
      _current = body();
      await _current;
    } on Exception catch (e, s) {
      print(e);
      print(s);
    } finally {
      _current = null;
    }
  }

  /// Waits for pending IndexedDB operations
  Future<void> flush() async {
    _checkClosed();
    if (_current != null) {
      try {
        await Future.wait([_current!]);
      } on Exception catch (_) {
      } finally {
        _current = null;
      }
    }
  }

  void _writeFileAsync(String path) {
    Future.sync(() async {
      await _mutex(() => _writeFile(path));
    });
  }

  Future<void> _writeFile(String path) async {
    final transaction = _database.transaction(_objectName, 'readwrite');
    await transaction.objectStore(_objectName).put(
        Blob(<Uint8List>[_memory._files[path] ?? Uint8List(0)]),
        absolutePath(path));
  }

  @override
  void createFile(
    String path, {
    bool errorIfNotExists = false,
    bool errorIfAlreadyExists = false,
  }) {
    _checkClosed();
    final _path = _normalize(path);
    final exists = _memory.exists(_path);

    _memory.createFile(
      _path,
      errorIfAlreadyExists: errorIfAlreadyExists,
      errorIfNotExists: errorIfNotExists,
    );

    if (!exists) {
      // Just created, so write
      _writeFileAsync(_path);
    }
  }

  @override
  String createTemporaryFile() {
    _checkClosed();
    final path = _memory.createTemporaryFile();
    _writeFileAsync(path);
    return path;
  }

  @override
  void deleteFile(String path) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.deleteFile(_path);
    Future.sync(
      () => _mutex(() async {
        final transaction =
            _database.transactionStore(_objectName, 'readwrite');
        await transaction.objectStore(_objectName).delete(absolutePath(_path));
      }),
    );
  }

  @override
  Future<void> clear() async {
    _checkClosed();
    final _files = files();
    _memory.clear();
    await _mutex(() async {
      final transaction = _database.transactionStore(_objectName, 'readwrite');
      for (final file in _files) {
        final f = absolutePath(file);
        await transaction.objectStore(_objectName).delete(f);
      }
    });
  }

  @override
  bool exists(String path) {
    _checkClosed();
    final _path = _normalize(path);
    return _memory.exists(_path);
  }

  @override
  @Deprecated('Use files() instead')
  List<String> listFiles() => files();

  @override
  List<String> files() {
    _checkClosed();
    return _memory.files();
  }

  @override
  int read(String path, Uint8List target, int offset) {
    _checkClosed();
    final _path = _normalize(path);
    return _memory.read(_path, target, offset);
  }

  @override
  int sizeOfFile(String path) {
    _checkClosed();
    final _path = _normalize(path);
    return _memory.sizeOfFile(_path);
  }

  @override
  void truncateFile(String path, int length) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.truncateFile(_path, length);
    _writeFileAsync(_path);
  }

  @override
  void write(String path, Uint8List bytes, int offset) {
    _checkClosed();
    final _path = _normalize(path);
    _memory.write(_path, bytes, offset);
    _writeFileAsync(_path);
  }
}
