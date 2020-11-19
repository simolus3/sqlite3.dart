import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:sqlite3/src/ffi/memory.dart';

import 'constants.dart';
import 'sqlite3.ffi.dart';

export 'dart:ffi';

export 'constants.dart';
export 'memory.dart';
export 'prepare_support.dart';
export 'sqlite3.ffi.dart';

extension Utf8Utils on Pointer<char> {
  int get _length {
    final asBytes = cast<Uint8>();
    var length = 0;

    for (; asBytes[length] != 0; length++) {}
    return length;
  }

  String readString([int? length]) {
    final resolvedLength = length ??= _length;

    return utf8
        .decode(cast<Uint8>().asTypedList(resolvedLength).buffer.asUint8List());
  }
}

extension PointerUtils on Pointer<NativeType> {
  bool get isNullPointer => address == 0;

  Uint8List copyRange(int length) {
    final list = Uint8List(length);
    list.setAll(0, cast<Uint8>().asTypedList(length));
    return list;
  }
}

extension ValueUtils on Pointer<sqlite3_value> {
  /// Copies the value stored in the raw sqlite3_value object.
  Object? read(Bindings bindings) {
    final type = bindings.sqlite3_value_type(this);
    switch (type) {
      case SQLITE_INTEGER:
        return bindings.sqlite3_value_int64(this);
      case SQLITE_FLOAT:
        return bindings.sqlite3_value_double(this);
      case SQLITE_TEXT:
        final length = bindings.sqlite3_value_bytes(this);
        return bindings.sqlite3_value_text(this).readString(length);
      case SQLITE_BLOB:
        final length = bindings.sqlite3_value_bytes(this);
        if (length == 0) {
          // sqlite3_column_blob returns a null pointer for non-null blobs with
          // a length of 0. Note that we can distinguish this from a proper null
          // by checking the type (which isn't SQLITE_NULL)
          return Uint8List(0);
        }
        return bindings.sqlite3_value_blob(this).copyRange(length);
      case SQLITE_NULL:
      default:
        return null;
    }
  }
}

extension ContextUtils on Pointer<sqlite3_context> {
  Pointer<Void> aggregateContext(Bindings bindings, int bytes) {
    return bindings.sqlite3_aggregate_context(this, bytes);
  }

  Pointer<Void> getUserData(Bindings bindings) {
    return bindings.sqlite3_user_data(this);
  }

  void setResult(Bindings bindings, Object? result) {
    if (result == null) {
      bindings.sqlite3_result_null(this);
    } else if (result is int) {
      bindings.sqlite3_result_int64(this, result);
    } else if (result is double) {
      bindings.sqlite3_result_double(this, result);
    } else if (result is bool) {
      bindings.sqlite3_result_int64(this, result ? 1 : 0);
    } else if (result is String) {
      final bytes = utf8.encode(result);
      final ptr = allocateBytes(bytes);

      bindings.sqlite3_result_text(
          this, ptr.cast(), bytes.length, SQLITE_TRANSIENT);
      ptr.free();
    } else if (result is List<int>) {
      final ptr = allocateBytes(result);

      bindings.sqlite3_result_blob64(
          this, ptr.cast(), result.length, SQLITE_TRANSIENT);
      ptr.free();
    }
  }

  void setError(Bindings bindings, String description) {
    final bytes = utf8.encode(description);
    final ptr = allocateBytes(bytes);

    bindings.sqlite3_result_error(this, ptr.cast(), bytes.length);
    ptr.free();
  }
}

/// An unmodifiable Dart list backed by native sqlite3 values.
class ValueList extends ListBase<Object?> {
  @override
  final int length;
  final Pointer<Pointer<sqlite3_value>> argArray;
  final Bindings bindings;

  bool isValid = true;

  final List<Object?> _cachedCopies;

  ValueList(this.length, this.argArray, this.bindings)
      : _cachedCopies = List.filled(length, null);

  @override
  set length(int length) {
    throw UnsupportedError('Changing the length of sql arguments in Dart');
  }

  @override
  Object? operator [](int index) {
    assert(
      isValid,
      'Invalid arguments. This commonly happens when an application-defined '
      'sql function leaks its arguments after it finishes running. '
      'Please use List.of(arguments) in the function to create a copy of '
      'the argument instead.',
    );
    RangeError.checkValidIndex(index, this, 'index', length);

    final cached = _cachedCopies[index];
    if (cached != null) {
      return cached;
    }

    final result = argArray[index].read(bindings);
    if (result is String || result is List<int>) {
      // Cache to avoid excessive copying in case the argument is loaded
      // multiple times
      _cachedCopies[index] = result;
    }

    return result;
  }

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('The argument list is mutable');
  }
}
