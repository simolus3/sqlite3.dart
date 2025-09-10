import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi;
import 'package:meta/meta.dart';

import '../constants.dart';
import '../exception.dart';
import '../functions.dart';
import '../implementation/bindings.dart';
import '../implementation/exception.dart';
import '../vfs.dart';
import 'generated/dynamic_library.dart';
import 'generated/native_library.dart' as native;
import 'memory.dart';
import 'generated/shared.dart';

// ignore_for_file: non_constant_identifier_names

class BindingsWithLibrary {
  // sqlite3_prepare_v3 was added in 3.20.0
  static const int _firstVersionForV3 = 3020000;

  // sqlite3_prepare_v3 was added in 3.38.0
  static const int _firstVersionForErrorOffset = 3038000;

  final SqliteLibrary bindings;
  final DynamicLibrary? library;
  final NativeFinalizer? sessionDelete;
  final NativeFinalizer? changesetIteratorFinalize;

  final bool supportsPrepareV3;
  final bool supportsErrorOffset;
  final bool supportsColumnTableName;

  factory BindingsWithLibrary(DynamicLibrary library) {
    final bindings = NativeLibrary(library);
    var hasColumnMetadata = false;

    if (library.providesSymbol('sqlite3_compileoption_get')) {
      var i = 0;
      String? lastOption;
      do {
        final ptr = bindings.sqlite3_compileoption_get(i);

        if (!ptr.isNullPointer) {
          lastOption = ptr.readString();

          if (lastOption == 'ENABLE_COLUMN_METADATA') {
            hasColumnMetadata = true;
            break;
          }
        } else {
          lastOption = null;
        }

        i++;
      } while (lastOption != null);
    }

    return BindingsWithLibrary._(
      bindings: bindings,
      library: library,
      supportsColumnTableName: hasColumnMetadata,
    );
  }

  factory BindingsWithLibrary.native() {
    final bindings = native.NativeAssetsLibrary();

    return BindingsWithLibrary._(
      bindings: bindings,
      library: null,
      supportsColumnTableName: false,
    );
  }

  BindingsWithLibrary._({
    required this.bindings,
    required this.library,
    required this.supportsColumnTableName,
  })  : supportsErrorOffset =
            bindings.sqlite3_libversion_number() >= _firstVersionForErrorOffset,
        supportsPrepareV3 =
            bindings.sqlite3_libversion_number() >= _firstVersionForV3,
        sessionDelete = _sessionDeleteFinalizer(library, bindings),
        changesetIteratorFinalize =
            _changesetFinalizeFinalizer(library, bindings);

  static NativeFinalizer? _sessionDeleteFinalizer(
      DynamicLibrary? library, SqliteLibrary bindings) {
    if (library != null && !library.providesSymbol('sqlite3session_delete')) {
      return null;
    }

    return NativeFinalizer(bindings.addresses.sqlite3session_delete.cast());
  }

  static NativeFinalizer? _changesetFinalizeFinalizer(
      DynamicLibrary? library, SqliteLibrary bindings) {
    if (library != null &&
        !library.providesSymbol('sqlite3changeset_finalize')) {
      return null;
    }

    return NativeFinalizer(bindings.addresses.sqlite3changeset_finalize.cast());
  }
}

final class FfiBindings extends RawSqliteBindings {
  final BindingsWithLibrary bindings;
  final _vfsPointers = Expando<_RegisteredVfs>();

  FfiBindings(this.bindings);

  @override
  RawSqliteSession sqlite3session_create(
    RawSqliteDatabase db,
    String name,
  ) {
    final dbImpl = db as FfiDatabase;
    final namePtr = Utf8Utils.allocateZeroTerminated(name);
    final sessionPtr = allocate<Pointer<sqlite3_session>>();
    final result = bindings.bindings.sqlite3session_create(
      dbImpl.db,
      namePtr,
      sessionPtr,
    );
    namePtr.free();
    final sessionValue = sessionPtr.value;
    sessionPtr.free();

    if (result != 0) {
      throw createExceptionOutsideOfDatabase(this, result);
    }

    return FfiSession(this, sessionValue);
  }

  @override
  int sqlite3changeset_apply(
    RawSqliteDatabase database,
    Uint8List changeset,
    int Function(
      String tableName,
    )? filter,
    int Function(
      int eConflict,
      RawChangesetIterator iter,
    ) conflict,
  ) {
    final dbImpl = database as FfiDatabase;
    final changesetPtr = allocateBytes(changeset);
    final ctxPtr = dbImpl.db.cast<Void>();

    final NativeCallable<Int Function(Pointer<Void>, Pointer<Char>)>?
        filterImpl = filter == null
            ? null
            : (NativeCallable.isolateLocal(
                (Pointer<Void> ctx, Pointer<Char> zTab) {
                  final tbl = zTab.cast<sqlite3_char>().readString();
                  return filter(tbl);
                },
                exceptionalReturn: 1,
              )..keepIsolateAlive = true);

    final NativeCallable<
            Int Function(Pointer<Void>, Int, Pointer<sqlite3_changeset_iter>)>
        conflictImpl = (NativeCallable.isolateLocal(
      (Pointer<Void> ctx, int eConflict, Pointer<sqlite3_changeset_iter> p) {
        final iter = FfiChangesetIterator(this, p, ownsIterator: false);
        return conflict(eConflict, iter);
      },
      exceptionalReturn: 1,
    )..keepIsolateAlive = true);

    final result = bindings.bindings.sqlite3changeset_apply(
      dbImpl.db,
      changeset.length,
      changesetPtr.cast(),
      filterImpl?.nativeFunction ?? nullPtr(),
      conflictImpl.nativeFunction,
      ctxPtr,
    );
    changesetPtr.free();
    filterImpl?.close();
    conflictImpl.close();

    return result;
  }

  @override
  RawChangesetIterator sqlite3changeset_start(Uint8List changeset) {
    final (asPtr, region) = allocateBytesWithFinalizer(changeset);
    final iteratorOut = allocate<Pointer<sqlite3_changeset_iter>>();

    final result = bindings.bindings
        .sqlite3changeset_start(iteratorOut, changeset.length, asPtr.cast());
    final iterator = iteratorOut.value;
    iteratorOut.free();

    if (result != SqlError.SQLITE_OK) {
      asPtr.free();
      throw createExceptionOutsideOfDatabase(this, result);
    }

    return FfiChangesetIterator(this, iterator,
        ownsIterator: true, ownedChangesetBytes: region);
  }

  @override
  Uint8List sqlite3changeset_invert(Uint8List changeset) {
    final sessionPtr = allocateBytes(changeset).cast<Void>();
    final outSize = allocate<Int>();
    final outChangeset = allocate<Pointer<Void>>();

    try {
      final result = bindings.bindings.sqlite3changeset_invert(
        changeset.length,
        sessionPtr,
        outSize,
        outChangeset,
      );

      if (result != SqlError.SQLITE_OK) {
        throw createExceptionOutsideOfDatabase(this, result);
      }

      final size = outSize.value;
      final inverted = outChangeset.value.cast<Uint8>().asTypedList(size,
          finalizer: bindings.bindings.addresses.sqlite3_free.cast());
      return inverted;
    } finally {
      sessionPtr.free();
      outSize.free();
      outChangeset.free();
    }
  }

  @override
  String? get sqlite3_temp_directory {
    return bindings.bindings.sqlite3_temp_directory.readNullableString();
  }

  @override
  set sqlite3_temp_directory(String? value) {
    if (value == null) {
      bindings.bindings.sqlite3_temp_directory = nullPtr();
    } else {
      bindings.bindings.sqlite3_temp_directory =
          Utf8Utils.allocateZeroTerminated(value);
    }
  }

  @override
  int sqlite3_initialize() {
    return bindings.bindings.sqlite3_initialize();
  }

  @override
  String sqlite3_errstr(int extendedErrorCode) {
    return bindings.bindings.sqlite3_errstr(extendedErrorCode).readString();
  }

  @override
  String sqlite3_libversion() {
    return bindings.bindings.sqlite3_libversion().readString();
  }

  @override
  int sqlite3_libversion_number() {
    return bindings.bindings.sqlite3_libversion_number();
  }

  @override
  SqliteResult<RawSqliteDatabase> sqlite3_open_v2(
      String name, int flags, String? zVfs) {
    final namePtr = Utf8Utils.allocateZeroTerminated(name);
    final outDb = allocate<Pointer<sqlite3>>();
    final vfsPtr = zVfs == null
        ? nullPtr<sqlite3_char>()
        : Utf8Utils.allocateZeroTerminated(zVfs);

    final resultCode =
        bindings.bindings.sqlite3_open_v2(namePtr, outDb, flags, vfsPtr);
    final result = SqliteResult(resultCode, FfiDatabase(bindings, outDb.value));

    namePtr.free();
    outDb.free();
    if (zVfs != null) vfsPtr.free();

    return result;
  }

  @override
  String sqlite3_sourceid() {
    return bindings.bindings.sqlite3_sourceid().readString();
  }

  @override
  void registerVirtualFileSystem(VirtualFileSystem vfs, int makeDefault) {
    final ptr = _RegisteredVfs.allocate(vfs);
    final result =
        bindings.bindings.sqlite3_vfs_register(ptr._vfsPtr, makeDefault);
    if (result != SqlError.SQLITE_OK) {
      ptr.deallocate();
      throw SqliteException(result, 'Could not register VFS.');
    }

    _vfsPointers[vfs] = ptr;
  }

  @override
  void unregisterVirtualFileSystem(VirtualFileSystem vfs) {
    final ptr = _vfsPointers[vfs];
    if (ptr == null) {
      throw StateError('vfs has not been registered');
    }

    final result = bindings.bindings.sqlite3_vfs_unregister(ptr._vfsPtr);
    if (result != SqlError.SQLITE_OK) {
      throw SqliteException(result, 'Could not unregister VFS.');
    }

    ptr.deallocate();
  }
}

final class _RegisteredVfs {
  static final Map<int, VirtualFileSystemFile> _files = {};
  static final Map<int, VirtualFileSystem> _vfs = {};

  static int _vfsCounter = 0;
  static int _fileCounter = 0;

  final Pointer<sqlite3_vfs> _vfsPtr;
  final Pointer<Char> _name;

  _RegisteredVfs(this._vfsPtr, this._name);

  factory _RegisteredVfs.allocate(VirtualFileSystem dartVfs) {
    final name = Utf8Utils.allocateZeroTerminated(dartVfs.name).cast<Char>();
    final id = _vfsCounter++;

    final vfs = ffi.calloc<sqlite3_vfs>();
    vfs.ref
      ..iVersion = 2 // We don't support syscalls yet
      ..szOsFile = sizeOf<_DartFile>()
      ..mxPathname = 1024
      ..zName = name
      ..pAppData = Pointer.fromAddress(id)
      ..xOpen = Pointer.fromFunction(_xOpen, SqlError.SQLITE_ERROR)
      ..xDelete = Pointer.fromFunction(_xDelete, SqlError.SQLITE_ERROR)
      ..xAccess = Pointer.fromFunction(_xAccess, SqlError.SQLITE_ERROR)
      ..xFullPathname =
          Pointer.fromFunction(_xFullPathname, SqlError.SQLITE_ERROR)
      ..xDlOpen = nullPtr()
      ..xDlError = nullPtr()
      ..xDlSym = nullPtr()
      ..xDlClose = nullPtr()
      ..xRandomness = Pointer.fromFunction(_xRandomness, SqlError.SQLITE_ERROR)
      ..xSleep = Pointer.fromFunction(_xSleep, SqlError.SQLITE_ERROR)
      ..xCurrentTime = nullPtr()
      ..xGetLastError = nullPtr()
      ..xCurrentTimeInt64 =
          Pointer.fromFunction(_xCurrentTime64, SqlError.SQLITE_ERROR);

    _vfs[id] = dartVfs;
    return _RegisteredVfs(vfs, name);
  }

  void deallocate() {
    _vfs.remove(_vfsPtr.ref.pAppData.address);
    ffi.calloc.free(_vfsPtr);
    _name.free();
  }

  static int _runVfs(
      Pointer<sqlite3_vfs> vfs, void Function(VirtualFileSystem) body) {
    final dartVfs = _vfs[vfs.ref.pAppData.address]!;
    try {
      body(dartVfs);
      return SqlError.SQLITE_OK;
    } on VfsException catch (e) {
      return e.returnCode;
    } on Object {
      return SqlError.SQLITE_ERROR;
    }
  }

  static int _xOpen(Pointer<sqlite3_vfs> vfsPtr, Pointer<Char> zName,
      Pointer<sqlite3_file> file, int flags, Pointer<Int> pOutFlags) {
    return _runVfs(vfsPtr, (vfs) {
      final fileName = Sqlite3Filename(
          zName.isNullPointer ? null : zName.cast<sqlite3_char>().readString());
      final dartFilePtr = file.cast<_DartFile>();

      final (file: dartFile, :outFlags) = vfs.xOpen(fileName, flags);
      final fileId = _fileCounter++;
      _files[fileId] = dartFile;

      final ioMethods = ffi.calloc<sqlite3_io_methods>();
      ioMethods.ref
        ..iVersion = 1
        ..xClose = Pointer.fromFunction(_xClose, SqlError.SQLITE_ERROR)
        ..xRead = Pointer.fromFunction(_xRead, SqlError.SQLITE_ERROR)
        ..xWrite = Pointer.fromFunction(_xWrite, SqlError.SQLITE_ERROR)
        ..xTruncate = Pointer.fromFunction(_xTruncate, SqlError.SQLITE_ERROR)
        ..xSync = Pointer.fromFunction(_xSync, SqlError.SQLITE_ERROR)
        ..xFileSize = Pointer.fromFunction(_xFileSize, SqlError.SQLITE_ERROR)
        ..xLock = Pointer.fromFunction(_xLock, SqlError.SQLITE_ERROR)
        ..xUnlock = Pointer.fromFunction(_xUnlock, SqlError.SQLITE_ERROR)
        ..xCheckReservedLock =
            Pointer.fromFunction(_xCheckReservedLock, SqlError.SQLITE_ERROR)
        ..xFileControl =
            Pointer.fromFunction(_xFileControl, SqlError.SQLITE_NOTFOUND)
        ..xSectorSize = Pointer.fromFunction(_xSectorSize, 4096)
        ..xDeviceCharacteristics =
            Pointer.fromFunction(_xDeviveCharacteristics, 0);

      if (!pOutFlags.isNullPointer) {
        pOutFlags.value = outFlags;
      }

      dartFilePtr.ref
        ..pMethods = ioMethods
        ..dartFileId = fileId;
    });
  }

  static int _xDelete(
      Pointer<sqlite3_vfs> vfsPtr, Pointer<Char> zName, int syncDir) {
    return _runVfs(vfsPtr,
        (vfs) => vfs.xDelete(zName.cast<sqlite3_char>().readString(), syncDir));
  }

  static int _xAccess(Pointer<sqlite3_vfs> vfsPtr, Pointer<Char> zName,
      int flags, Pointer<Int> pResOut) {
    return _runVfs(vfsPtr, (vfs) {
      if (!pResOut.isNullPointer) {
        pResOut.value =
            vfs.xAccess(zName.cast<sqlite3_char>().readString(), flags);
      }
    });
  }

  static int _xFullPathname(Pointer<sqlite3_vfs> vfsPtr, Pointer<Char> zName,
      int nOut, Pointer<Char> zOut) {
    return _runVfs(vfsPtr, (vfs) {
      final bytes = utf8
          .encode(vfs.xFullPathName(zName.cast<sqlite3_char>().readString()));
      if (bytes.length >= nOut) {
        throw VfsException(SqlError.SQLITE_TOOBIG);
      }

      final target = zOut.cast<Uint8>().asTypedList(nOut);
      target.setAll(0, bytes);
      target[bytes.length] = 0;
    });
  }

  static int _xRandomness(
      Pointer<sqlite3_vfs> vfsPtr, int nByte, Pointer<Char> zOut) {
    return _runVfs(vfsPtr, (vfs) {
      vfs.xRandomness(zOut.cast<Uint8>().asTypedList(nByte));
    });
  }

  static int _xSleep(Pointer<sqlite3_vfs> vfsPtr, int microseconds) {
    return _runVfs(
        vfsPtr, (vfs) => vfs.xSleep(Duration(microseconds: microseconds)));
  }

  static int _xCurrentTime64(Pointer<sqlite3_vfs> vfsPtr, Pointer<Int64> out) {
    return _runVfs(vfsPtr, (vfs) {
      if (!out.isNullPointer) {
        // https://github.com/sqlite/sqlite/blob/8ee75f7c3ac1456b8d941781857be27bfddb57d6/src/os_unix.c#L6757
        const unixEpoch = 24405875 * 8640000;

        out.value = unixEpoch + vfs.xCurrentTime().millisecondsSinceEpoch;
      }
    });
  }

  static int _runFile(
      Pointer<sqlite3_file> file, void Function(VirtualFileSystemFile) body) {
    final id = file.cast<_DartFile>().ref.dartFileId;
    final dartFile = _files[id]!;
    try {
      body(dartFile);
      return SqlError.SQLITE_OK;
    } on VfsException catch (e) {
      return e.returnCode;
    } on Object {
      return SqlError.SQLITE_ERROR;
    }
  }

  static int _xClose(Pointer<sqlite3_file> ptr) {
    return _runFile(ptr, (file) {
      file.xClose();

      final dartFile = ptr.cast<_DartFile>().ref;
      _files.remove(dartFile.dartFileId);
      ffi.calloc.free(dartFile.pMethods);
    });
  }

  static int _xRead(
      Pointer<sqlite3_file> ptr, Pointer<Void> target, int amount, int offset) {
    return _runFile(ptr, (file) {
      final buffer = target.cast<Uint8>().asTypedList(amount);
      file.xRead(buffer, offset);
    });
  }

  static int _xWrite(
      Pointer<sqlite3_file> ptr, Pointer<Void> target, int amount, int offset) {
    return _runFile(ptr, (file) {
      final buffer = target.cast<Uint8>().asTypedList(amount);
      file.xWrite(buffer, offset);
    });
  }

  static int _xTruncate(Pointer<sqlite3_file> ptr, int size) {
    return _runFile(ptr, (file) => file.xTruncate(size));
  }

  static int _xSync(Pointer<sqlite3_file> ptr, int flags) {
    return _runFile(ptr, (file) => file.xSync(flags));
  }

  static int _xFileSize(Pointer<sqlite3_file> ptr, Pointer<Int64> pSize) {
    return _runFile(ptr, (file) {
      if (!pSize.isNullPointer) {
        pSize.value = file.xFileSize();
      }
    });
  }

  static int _xLock(Pointer<sqlite3_file> ptr, int flags) {
    return _runFile(ptr, (file) => file.xLock(flags));
  }

  static int _xUnlock(Pointer<sqlite3_file> ptr, int flags) {
    return _runFile(ptr, (file) => file.xUnlock(flags));
  }

  static int _xCheckReservedLock(
      Pointer<sqlite3_file> ptr, Pointer<Int> pResOut) {
    return _runFile(ptr, (file) {
      if (!pResOut.isNullPointer) {
        pResOut.value = file.xCheckReservedLock();
      }
    });
  }

  static int _xFileControl(
      Pointer<sqlite3_file> ptr, int op, Pointer<Void> pArg) {
    // We don't currently support filecontrol operations in the VFS.
    return SqlError.SQLITE_NOTFOUND;
  }

  static int _xSectorSize(Pointer<sqlite3_file> ptr) {
    // We don't currently support custom sector sizes.
    return 4096;
  }

  static int _xDeviveCharacteristics(Pointer<sqlite3_file> ptr) {
    return _runFile(ptr, (file) => file.xDeviceCharacteristics);
  }
}

final class _DartFile extends Struct {
  // extends sqlite3_file:
  external Pointer<sqlite3_io_methods> pMethods;
  // additional definitions
  @Int64()
  external int dartFileId;
}

final class FfiSession extends RawSqliteSession implements Finalizable {
  final FfiBindings bindings;
  final Pointer<sqlite3_session> session;
  final Object detachToken = Object();

  SqliteLibrary get _library => bindings.bindings.bindings;

  FfiSession(this.bindings, this.session) {
    bindings.bindings.sessionDelete
        ?.attach(this, session.cast(), detach: detachToken);
  }

  @override
  int sqlite3session_attach([String? name]) {
    final namePtr = name == null
        ? nullPtr<sqlite3_char>()
        : Utf8Utils.allocateZeroTerminated(name);
    final result = _library.sqlite3session_attach(
      session,
      namePtr,
    );
    if (name != null) {
      namePtr.free();
    }
    return result;
  }

  Uint8List _handleChangesetResult(int result, int size, Pointer<Void> buffer) {
    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }

    return buffer
        .cast<Uint8>()
        .asTypedList(size, finalizer: _library.addresses.sqlite3_free);
  }

  @override
  Uint8List sqlite3session_changeset() {
    final outSize = allocate<Int>();
    final outChangeset = allocate<Pointer<Void>>();
    final result = _library.sqlite3session_changeset(
      session,
      outSize,
      outChangeset,
    );

    final size = outSize.value;
    final changeset = outChangeset.value;
    outSize.free();
    outChangeset.free();

    return _handleChangesetResult(result, size, changeset);
  }

  @override
  Uint8List sqlite3session_patchset() {
    final outSize = allocate<Int>();
    final outPatchset = allocate<Pointer<Void>>();
    final result = _library.sqlite3session_patchset(
      session,
      outSize,
      outPatchset,
    );

    final size = outSize.value;
    final patchset = outPatchset.value;
    outSize.free();
    outPatchset.free();

    return _handleChangesetResult(result, size, patchset);
  }

  @override
  void sqlite3session_delete() {
    bindings.bindings.sessionDelete?.detach(detachToken);
    _library.sqlite3session_delete(session);
  }

  @override
  int sqlite3session_diff(String fromDb, String table) {
    final fromDbPtr = Utf8Utils.allocateZeroTerminated(fromDb);
    final tablePtr = Utf8Utils.allocateZeroTerminated(table);
    final result = _library.sqlite3session_diff(
      session,
      fromDbPtr,
      tablePtr,
      nullPtr(),
    );
    fromDbPtr.free();
    tablePtr.free();
    return result;
  }

  @override
  int sqlite3session_enable(int enable) {
    return _library.sqlite3session_enable(session, enable);
  }

  @override
  int sqlite3session_indirect(int indirect) {
    return _library.sqlite3session_indirect(session, indirect);
  }

  @override
  int sqlite3session_isempty() {
    return _library.sqlite3session_isempty(session);
  }
}

final class FfiChangesetIterator extends RawChangesetIterator
    implements Finalizable {
  final FfiBindings bindings;

  final Pointer<sqlite3_changeset_iter> iterator;
  final Object detachToken = Object();

  /// An optional [Uint8List] backing the changeset we're iterating on with a
  /// native finalizer attached to it.
  ///
  /// This ensures that, as the iterator is GCed, so is the changeset.
  final Uint8List? ownedChangesetBytes;

  SqliteLibrary get _library => bindings.bindings.bindings;

  FfiChangesetIterator(this.bindings, this.iterator,
      {bool ownsIterator = true, this.ownedChangesetBytes}) {
    if (ownsIterator) {
      bindings.bindings.changesetIteratorFinalize
          ?.attach(this, iterator.cast(), detach: detachToken);
    }
  }

  @override
  int sqlite3changeset_finalize() {
    bindings.bindings.changesetIteratorFinalize?.detach(detachToken);
    final result = _library.sqlite3changeset_finalize(iterator);
    return result;
  }

  @override
  SqliteResult<RawSqliteValue?> sqlite3changeset_new(int columnNumber) {
    final outValue = allocate<Pointer<sqlite3_value>>();
    final result = _library.sqlite3changeset_new(
      iterator,
      columnNumber,
      outValue,
    );
    final value = outValue.value;
    outValue.free();

    return SqliteResult(
        result, value.isNullPointer ? null : FfiValue(_library, value));
  }

  @override
  int sqlite3changeset_next() {
    return _library.sqlite3changeset_next(iterator);
  }

  @override
  SqliteResult<RawSqliteValue?> sqlite3changeset_old(int columnNumber) {
    final outValue = allocate<Pointer<sqlite3_value>>();
    final result = _library.sqlite3changeset_old(
      iterator,
      columnNumber,
      outValue,
    );
    final value = outValue.value;
    outValue.free();

    return SqliteResult(
        result, value.isNullPointer ? null : FfiValue(_library, value));
  }

  @override
  RawChangeSetOp sqlite3changeset_op() {
    final tablePtr = allocate<Pointer<sqlite3_char>>();
    final columnCountPtr = allocate<Int>();
    final typePtr = allocate<Int>();
    final indirectPtr = allocate<Int>();

    final result = _library.sqlite3changeset_op(
      iterator,
      tablePtr,
      columnCountPtr,
      typePtr,
      indirectPtr,
    );

    final tableValue = tablePtr.value;
    final columnCountValue = columnCountPtr.value;
    final typeValue = typePtr.value;
    final indirectValue = indirectPtr.value;
    tablePtr.free();
    columnCountPtr.free();
    typePtr.free();
    indirectPtr.free();

    if (result != SqlError.SQLITE_OK) {
      throw createExceptionOutsideOfDatabase(bindings, result);
    }

    final table = tableValue.readString();
    return RawChangeSetOp(
      tableName: table,
      columnCount: columnCountValue,
      operation: typeValue,
      indirect: indirectValue,
    );
  }
}

final class FfiDatabase extends RawSqliteDatabase {
  final BindingsWithLibrary bindings;
  final Pointer<sqlite3> db;
  NativeCallable<_UpdateHook>? _installedUpdateHook;
  NativeCallable<_CommitHook>? _installedCommitHook;
  NativeCallable<_RollbackHook>? _installedRollbackHook;

  FfiDatabase(this.bindings, this.db);

  @override
  int sqlite3_close_v2() {
    return bindings.bindings.sqlite3_close_v2(db);
  }

  @override
  String sqlite3_errmsg() {
    return bindings.bindings.sqlite3_errmsg(db).readString();
  }

  @override
  int sqlite3_extended_errcode() {
    return bindings.bindings.sqlite3_extended_errcode(db);
  }

  @override
  int sqlite3_error_offset() {
    if (bindings.supportsErrorOffset) {
      return bindings.bindings.sqlite3_error_offset(db);
    } else {
      return -1;
    }
  }

  @override
  void sqlite3_extended_result_codes(int onoff) {
    bindings.bindings.sqlite3_extended_result_codes(db, onoff);
  }

  @override
  int sqlite3_changes() => bindings.bindings.sqlite3_changes(db);

  @override
  int sqlite3_exec(String sql) {
    final sqlPtr = Utf8Utils.allocateZeroTerminated(sql);

    final result = bindings.bindings
        .sqlite3_exec(db, sqlPtr, nullPtr(), nullPtr(), nullPtr());
    sqlPtr.free();
    return result;
  }

  @override
  int sqlite3_last_insert_rowid() {
    return bindings.bindings.sqlite3_last_insert_rowid(db);
  }

  @override
  void deallocateAdditionalMemory() {}

  @override
  int sqlite3_create_collation_v2({
    required Uint8List collationName,
    required int eTextRep,
    required RawCollation collation,
  }) {
    final name = allocateBytes(collationName, additionalLength: 1);
    final bindings = this.bindings.bindings;
    final compare = collation.toNative(bindings);

    final result = bindings.sqlite3_create_collation_v2(
      db,
      name.cast(),
      eTextRep,
      nullPtr(),
      compare.nativeFunction,
      _xDestroy([compare]),
    );
    name.free();

    return result;
  }

  @override
  int sqlite3_create_window_function({
    required Uint8List functionName,
    required int nArg,
    required int eTextRep,
    required RawXStep xStep,
    required RawXFinal xFinal,
    required RawXFinal xValue,
    required RawXStep xInverse,
  }) {
    final functionNamePtr = allocateBytes(functionName, additionalLength: 1);

    final bindings = this.bindings.bindings;
    final step = xStep.toNative(bindings);
    final $final = xFinal.toNative(bindings, true);
    final value = xValue.toNative(bindings, false);
    final inverse = xInverse.toNative(bindings);

    final result = bindings.sqlite3_create_window_function(
      db,
      functionNamePtr.cast(),
      nArg,
      eTextRep,
      nullPtr(),
      step.nativeFunction,
      $final.nativeFunction,
      value.nativeFunction,
      inverse.nativeFunction,
      _xDestroy([step, $final, value, inverse]),
    );
    functionNamePtr.free();
    return result;
  }

  @override
  int sqlite3_create_function_v2({
    required Uint8List functionName,
    required int nArg,
    required int eTextRep,
    RawXFunc? xFunc,
    RawXStep? xStep,
    RawXFinal? xFinal,
  }) {
    final functionNamePtr = allocateBytes(functionName, additionalLength: 1);

    final bindings = this.bindings.bindings;
    final func = xFunc?.toNative(bindings);
    final step = xStep?.toNative(bindings);
    final $final = xFinal?.toNative(bindings, true);

    final result = bindings.sqlite3_create_function_v2(
      db,
      functionNamePtr.cast(),
      nArg,
      eTextRep,
      nullPtr(),
      func?.nativeFunction ?? nullPtr(),
      step?.nativeFunction ?? nullPtr(),
      $final?.nativeFunction ?? nullPtr(),
      _xDestroy([
        if (func != null) func,
        if (step != null) step,
        if ($final != null) $final,
      ]),
    );
    functionNamePtr.free();
    return result;
  }

  @override
  void sqlite3_update_hook(RawUpdateHook? hook) {
    final previous = _installedUpdateHook;

    if (hook == null) {
      _installedUpdateHook = null;
      bindings.bindings.sqlite3_update_hook(db, nullPtr(), nullPtr());
    } else {
      final native = _installedUpdateHook = hook.toNative();
      bindings.bindings
          .sqlite3_update_hook(db, native.nativeFunction, nullPtr());
    }

    previous?.close();
  }

  @override
  void sqlite3_commit_hook(RawCommitHook? hook) {
    final previous = _installedCommitHook;

    if (hook == null) {
      _installedCommitHook = null;
      bindings.bindings.sqlite3_commit_hook(db, nullPtr(), nullPtr());
    } else {
      final native = _installedCommitHook = hook.toNative();
      bindings.bindings
          .sqlite3_commit_hook(db, native.nativeFunction, nullPtr());
    }

    previous?.close();
  }

  @override
  void sqlite3_rollback_hook(RawRollbackHook? hook) {
    final previous = _installedRollbackHook;

    if (hook == null) {
      bindings.bindings.sqlite3_rollback_hook(db, nullPtr(), nullPtr());
    } else {
      final native = _installedRollbackHook = hook.toNative();
      bindings.bindings
          .sqlite3_rollback_hook(db, native.nativeFunction, nullPtr());
    }

    previous?.close();
  }

  @override
  int sqlite3_db_config(int op, int value) {
    final result = bindings.bindings.sqlite3_db_config(
      db,
      op,
      value,
      nullPtr(),
    );
    return result;
  }

  @override
  int sqlite3_get_autocommit() {
    return bindings.bindings.sqlite3_get_autocommit(db);
  }

  @override
  RawStatementCompiler newCompiler(List<int> utf8EncodedSql) {
    return FfiStatementCompiler(this, allocateBytes(utf8EncodedSql));
  }

  static Pointer<NativeFunction<Void Function(Pointer<Void>)>> _xDestroy(
      List<NativeCallable> callables) {
    void destroy(Pointer<Void> _) {
      for (final callable in callables) {
        callable.close();
      }
    }

    final callable =
        NativeCallable<Void Function(Pointer<Void>)>.isolateLocal(destroy)
          ..keepIsolateAlive = false;
    callables.add(callable);

    return callable.nativeFunction;
  }
}

final class FfiStatementCompiler extends RawStatementCompiler {
  final FfiDatabase database;
  final Pointer<Uint8> sql;
  final Pointer<Pointer<sqlite3_stmt>> stmtOut = allocate();
  final Pointer<Pointer<sqlite3_char>> pzTail = allocate();

  FfiStatementCompiler(this.database, this.sql);

  @override
  void close() {
    sql.free();
    stmtOut.free();
    pzTail.free();
  }

  @override
  int get endOffset => pzTail.value.address - sql.address;

  @override
  SqliteResult<RawSqliteStatement?> sqlite3_prepare(
      int byteOffset, int length, int prepFlag) {
    final int result;

    if (database.bindings.supportsPrepareV3) {
      result = database.bindings.bindings.sqlite3_prepare_v3(
        database.db,
        (sql + byteOffset).cast(),
        length,
        prepFlag,
        stmtOut,
        pzTail,
      );
    } else {
      assert(
        prepFlag == 0,
        'Used custom preparation flags, but the loaded sqlite library does '
        'not support prepare_v3',
      );

      result = database.bindings.bindings.sqlite3_prepare_v2(
        database.db,
        (sql + byteOffset).cast(),
        length,
        stmtOut,
        pzTail,
      );
    }

    final stmt = stmtOut.value;
    final libraryStatement =
        stmt.isNullPointer ? null : FfiStatement(database, stmt);

    return SqliteResult(result, libraryStatement);
  }
}

final class FfiStatement extends RawSqliteStatement {
  final FfiDatabase database;
  final SqliteLibrary bindings;
  final Pointer<sqlite3_stmt> stmt;

  final List<Pointer> _allocatedArguments = [];

  FfiStatement(this.database, this.stmt)
      : bindings = database.bindings.bindings;

  @visibleForTesting
  List<Pointer> get allocatedArguments => _allocatedArguments;

  @override
  void deallocateArguments() {
    for (final arg in _allocatedArguments) {
      arg.free();
    }
    _allocatedArguments.clear();
  }

  @override
  int sqlite3_bind_blob64(int index, List<int> value) {
    final ptr = allocateBytes(value);
    _allocatedArguments.add(ptr);

    return bindings.sqlite3_bind_blob64(
        stmt, index, ptr.cast(), value.length, nullPtr());
  }

  @override
  int sqlite3_bind_double(int index, double value) {
    return bindings.sqlite3_bind_double(stmt, index, value);
  }

  @override
  int sqlite3_bind_int64(int index, int value) {
    return bindings.sqlite3_bind_int64(stmt, index, value);
  }

  @override
  int sqlite3_bind_int64BigInt(int index, BigInt value) {
    return bindings.sqlite3_bind_int64(stmt, index, value.toInt());
  }

  @override
  int sqlite3_bind_null(int index) {
    return bindings.sqlite3_bind_null(stmt, index);
  }

  @override
  int sqlite3_bind_parameter_count() {
    return bindings.sqlite3_bind_parameter_count(stmt);
  }

  @override
  int sqlite3_stmt_isexplain() {
    return bindings.sqlite3_stmt_isexplain(stmt);
  }

  @override
  int sqlite3_stmt_readonly() {
    return bindings.sqlite3_stmt_readonly(stmt);
  }

  @override
  int sqlite3_bind_parameter_index(String name) {
    final ptr = Utf8Utils.allocateZeroTerminated(name);
    try {
      return bindings.sqlite3_bind_parameter_index(stmt, ptr);
    } finally {
      ptr.free();
    }
  }

  @override
  int sqlite3_bind_text(int index, String value) {
    final bytes = utf8.encode(value);
    final ptr = allocateBytes(bytes);
    _allocatedArguments.add(ptr);

    return bindings.sqlite3_bind_text(
        stmt, index, ptr.cast(), bytes.length, nullPtr());
  }

  @override
  Uint8List sqlite3_column_bytes(int index) {
    final length = bindings.sqlite3_column_bytes(stmt, index);
    if (length == 0) {
      // sqlite3_column_blob returns a null pointer for non-null blobs with
      // a length of 0. Note that we can distinguish this from a proper null
      // by checking the type (which isn't SQLITE_NULL)
      return Uint8List(0);
    }
    return bindings.sqlite3_column_blob(stmt, index).copyRange(length);
  }

  @override
  int sqlite3_column_count() {
    return bindings.sqlite3_column_count(stmt);
  }

  @override
  double sqlite3_column_double(int index) {
    return bindings.sqlite3_column_double(stmt, index);
  }

  @override
  int sqlite3_column_int64(int index) {
    return bindings.sqlite3_column_int64(stmt, index);
  }

  @override
  BigInt sqlite3_column_int64OrBigInt(int index) {
    return BigInt.from(bindings.sqlite3_column_int64(stmt, index));
  }

  @override
  String sqlite3_column_name(int index) {
    return bindings.sqlite3_column_name(stmt, index).readString();
  }

  @override
  String? sqlite3_column_table_name(int index) {
    return bindings.sqlite3_column_table_name(stmt, index).readNullableString();
  }

  @override
  String sqlite3_column_text(int index) {
    final length = bindings.sqlite3_column_bytes(stmt, index);
    return bindings.sqlite3_column_text(stmt, index).readString(length);
  }

  @override
  int sqlite3_column_type(int index) {
    return bindings.sqlite3_column_type(stmt, index);
  }

  @override
  void sqlite3_finalize() {
    bindings.sqlite3_finalize(stmt);
  }

  @override
  void sqlite3_reset() {
    bindings.sqlite3_reset(stmt);
  }

  @override
  int sqlite3_step() {
    return bindings.sqlite3_step(stmt);
  }

  @override
  bool get supportsReadingTableNameForColumn =>
      database.bindings.supportsColumnTableName;
}

final class FfiValue extends RawSqliteValue {
  final SqliteLibrary bindings;
  final Pointer<sqlite3_value> value;

  FfiValue(this.bindings, this.value) : assert(!value.isNullPointer);

  @override
  Uint8List sqlite3_value_blob() {
    final byteLength = bindings.sqlite3_value_bytes(value);
    return bindings.sqlite3_value_blob(value).copyRange(byteLength);
  }

  @override
  double sqlite3_value_double() {
    return bindings.sqlite3_value_double(value);
  }

  @override
  int sqlite3_value_int64() {
    return bindings.sqlite3_value_int64(value);
  }

  @override
  String sqlite3_value_text() {
    final byteLength = bindings.sqlite3_value_bytes(value);
    return utf8
        .decode(bindings.sqlite3_value_text(value).copyRange(byteLength));
  }

  @override
  int sqlite3_value_type() {
    return bindings.sqlite3_value_type(value);
  }

  @override
  int sqlite3_value_subtype() {
    return bindings.sqlite3_value_subtype(value);
  }
}

final class FfiContext extends RawSqliteContext {
  static int _aggregateContextId = 1;
  static final Map<int, AggregateContext<Object?>> _contexts = {};

  final SqliteLibrary bindings;
  final Pointer<sqlite3_context> context;

  FfiContext(this.bindings, this.context);

  Pointer<Int64> get _rawAggregateContext {
    final agCtxPtr = bindings
        .sqlite3_aggregate_context(context, sizeOf<Int64>())
        .cast<Int64>();

    if (agCtxPtr.isNullPointer) {
      // We can't run without our 8 bytes! This indicates an out-of-memory error
      throw StateError(
          'Internal error while allocating sqlite3 aggregate context (OOM?)');
    }

    return agCtxPtr;
  }

  @override
  AggregateContext<Object?>? get dartAggregateContext {
    final agCtxPtr = _rawAggregateContext;
    final value = agCtxPtr.value;

    // Ok, we have a pointer (that sqlite3 zeroes out for us). Our state counter
    // starts at one, so if it's still zero we don't have a Dart context yet.
    if (value == 0) {
      return null;
    } else {
      return _contexts[value];
    }
  }

  @override
  set dartAggregateContext(AggregateContext<Object?>? value) {
    final ptr = _rawAggregateContext;

    final id = _aggregateContextId++;
    _contexts[id] = ArgumentError.checkNotNull(value);
    ptr.value = id;
  }

  @override
  void sqlite3_result_blob64(List<int> blob) {
    final ptr = allocateBytes(blob);

    bindings.sqlite3_result_blob64(context, ptr.cast(), blob.length,
        Pointer.fromAddress(SqlSpecialDestructor.SQLITE_TRANSIENT));
    ptr.free();
  }

  @override
  void sqlite3_result_double(double value) {
    bindings.sqlite3_result_double(context, value);
  }

  @override
  void sqlite3_result_error(String message) {
    final ptr = allocateBytes(utf8.encode(message));

    bindings.sqlite3_result_error(context, ptr.cast(), message.length);
    ptr.free();
  }

  @override
  void sqlite3_result_int64(int value) {
    bindings.sqlite3_result_int64(context, value);
  }

  @override
  void sqlite3_result_int64BigInt(BigInt value) {
    bindings.sqlite3_result_int64(context, value.toInt());
  }

  @override
  void sqlite3_result_null() {
    bindings.sqlite3_result_null(context);
  }

  @override
  void sqlite3_result_text(String text) {
    final bytes = utf8.encode(text);
    final ptr = allocateBytes(bytes);

    bindings.sqlite3_result_text(context, ptr.cast(), bytes.length,
        Pointer.fromAddress(SqlSpecialDestructor.SQLITE_TRANSIENT));
    ptr.free();
  }

  @override
  void sqlite3_result_subtype(int value) {
    bindings.sqlite3_result_subtype(context, value);
  }

  void freeContext() {
    final ctxId = _rawAggregateContext.value;
    _contexts.remove(ctxId);
  }
}

class _ValueList extends ListBase<FfiValue> {
  @override
  int length;
  final Pointer<Pointer<sqlite3_value>> args;
  final SqliteLibrary bindings;

  _ValueList(this.length, this.args, this.bindings);

  @override
  FfiValue operator [](int index) {
    return FfiValue(bindings, args[index]);
  }

  @override
  void operator []=(int index, FfiValue value) {}
}

typedef _XFunc = Void Function(
    Pointer<sqlite3_context>, Int, Pointer<Pointer<sqlite3_value>>);
typedef _XFinal = Void Function(Pointer<sqlite3_context>);
typedef _XCompare = Int Function(
    Pointer<Void>, Int, Pointer<Void>, Int, Pointer<Void>);
typedef _UpdateHook = Void Function(
    Pointer<Void>, Int, Pointer<sqlite3_char>, Pointer<sqlite3_char>, Int64);
typedef _CommitHook = Int Function(Pointer<Void>);
typedef _RollbackHook = Void Function(Pointer<Void>);

extension on RawXFunc {
  NativeCallable<_XFunc> toNative(SqliteLibrary bindings) {
    return NativeCallable.isolateLocal((Pointer<sqlite3_context> ctx, int nArgs,
        Pointer<Pointer<sqlite3_value>> args) {
      this(FfiContext(bindings, ctx), _ValueList(nArgs, args, bindings));
    })
      ..keepIsolateAlive = false;
  }
}

extension on RawXFinal {
  NativeCallable<_XFinal> toNative(SqliteLibrary bindings, bool clean) {
    return NativeCallable.isolateLocal((Pointer<sqlite3_context> ctx) {
      final context = FfiContext(bindings, ctx);
      this(context);
      if (clean) context.freeContext();
    })
      ..keepIsolateAlive = false;
  }
}

extension on RawCollation {
  NativeCallable<_XCompare> toNative(SqliteLibrary bindings) {
    return NativeCallable.isolateLocal(
      (
        Pointer<Void> _,
        int lengthA,
        Pointer<Void> a,
        int lengthB,
        Pointer<Void> b,
      ) {
        final dartA = a.cast<sqlite3_char>().readNullableString(lengthA);
        final dartB = b.cast<sqlite3_char>().readNullableString(lengthB);

        return this(dartA, dartB);
      },
      exceptionalReturn: 0,
    )..keepIsolateAlive = false;
  }
}

extension on RawUpdateHook {
  NativeCallable<_UpdateHook> toNative() {
    return NativeCallable.isolateLocal(
      (Pointer<Void> _, int kind, Pointer<sqlite3_char> db,
          Pointer<sqlite3_char> table, int rowid) {
        final tableName = table.readString();
        this(kind, tableName, rowid);
      },
    )..keepIsolateAlive = false;
  }
}

extension on RawCommitHook {
  NativeCallable<_CommitHook> toNative() {
    return NativeCallable.isolateLocal(
      (Pointer<Void> _) {
        return this();
      },
      exceptionalReturn: 1,
    )..keepIsolateAlive = false;
  }
}

extension on RawRollbackHook {
  NativeCallable<_RollbackHook> toNative() {
    return NativeCallable.isolateLocal(
      (Pointer<Void> _) {
        this();
      },
    )..keepIsolateAlive = false;
  }
}
