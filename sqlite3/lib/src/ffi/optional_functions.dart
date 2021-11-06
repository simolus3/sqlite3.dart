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

typedef sqlite3_column_table_name_dart = Pointer<char> Function(
    Pointer<sqlite3_stmt> pStmt, int N);

Expando<bool> _usesV2 = Expando();
Expando<Pointer<NativeType>> _prepareFunction = Expando();
Expando<sqlite3_column_table_name_dart> _tableNameFunction = Expando();

// sqlite3_prepare_v3 was added in 3.20.0
const int _firstVersionForV3 = 3020000;

extension PrepareSupport on Bindings {
  void _ensureLoaded() {
    // Already set?
    if (_usesV2[this] != null) return;

    if (sqlite3_libversion_number() >= _firstVersionForV3) {
      _usesV2[this] = false;
      _prepareFunction[this] = library.lookup('sqlite3_prepare_v3');
    } else {
      _usesV2[this] = true;
      _prepareFunction[this] = library.lookup('sqlite3_prepare_v2');
    }

    final knownCompileOptions =
        library.providesSymbol('sqlite3_compileoption_get');
    if (knownCompileOptions) {
      final getOptions = library.lookupFunction<Pointer<Uint8> Function(Int32),
          Pointer<Uint8> Function(int)>('sqlite3_compileoption_get');
      final options = () sync* {
        var i = 0;
        String? lastOption;
        do {
          final ptr = getOptions(i).cast<char>();

          if (!ptr.isNullPointer) {
            lastOption = ptr.readString();
            yield lastOption;
          } else {
            lastOption = null;
          }

          i++;
        } while (lastOption != null);
      }();

      final hasTableName = options.contains('ENABLE_COLUMN_METADATA');

      if (hasTableName) {
        _tableNameFunction[this] = library.lookupFunction<
            Pointer<char> Function(Pointer<sqlite3_stmt>, Int32),
            sqlite3_column_table_name_dart>('sqlite3_column_table_name');
      }
    }
  }

  bool get supportsOpenV3 {
    _ensureLoaded();
    return !_usesV2[this]!;
  }

  Pointer<NativeType> get appropriateOpenFunction {
    _ensureLoaded();
    return _prepareFunction[this]!;
  }

  sqlite3_column_table_name_dart? get columnNameFunction {
    _ensureLoaded();
    return _tableNameFunction[this];
  }
}
