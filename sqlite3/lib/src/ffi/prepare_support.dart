import 'ffi.dart';

// Some old sqlite versions don't support sqlite3_prepare_v3, we fall back to
// sqlite3_prepare_v2 in those cases.

typedef sqlite3_prepare_v3_native = Int32 Function(
    Pointer<sqlite3>,
    Pointer<Void>,
    Int32,
    Uint32,
    Pointer<Pointer<sqlite3_stmt>>,
    Pointer<Pointer<char>>);
typedef sqlite3_prepare_v3_dart = int Function(
    Pointer<sqlite3> db,
    Pointer<Void> zSql,
    int nByte,
    int prepFlags,
    Pointer<Pointer<sqlite3_stmt>> ppStmt,
    Pointer<Pointer<char>> pzTail);

typedef sqlite3_prepare_v2_native = Int32 Function(
    Pointer<sqlite3>,
    Pointer<Void>,
    Int32,
    Pointer<Pointer<sqlite3_stmt>>,
    Pointer<Pointer<char>>);
typedef sqlite3_prepare_v2_dart = int Function(
    Pointer<sqlite3> db,
    Pointer<Void> zSql,
    int nByte,
    Pointer<Pointer<sqlite3_stmt>> ppStmt,
    Pointer<Pointer<char>> pzTail);

Expando<bool> _usesV2 = Expando();
Expando<Pointer<NativeType>> _prepareFunction = Expando();

extension PrepareSupport on Bindings {
  void _ensureLoaded() {
    // Already set?
    if (_usesV2[this] != null) return;

    try {
      final ptr = library.lookup('sqlite3_prepare_v3');
      _usesV2[this] = false;
      _prepareFunction[this] = ptr;
      // ignore: avoid_catching_errors
    } on ArgumentError {
      _usesV2[this] = true;
      _prepareFunction[this] = library.lookup('sqlite3_prepare_v2');
    }
  }

  bool get supportsOpenV3 {
    _ensureLoaded();
    return !_usesV2[this];
  }

  Pointer<NativeType> get appropriateOpenFunction {
    _ensureLoaded();
    return _prepareFunction[this];
  }
}
