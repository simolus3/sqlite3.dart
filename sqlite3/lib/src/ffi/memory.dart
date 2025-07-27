import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi;

import 'generated/shared.dart';

const allocate = ffi.malloc;

final freeFinalizer = NativeFinalizer(allocate.nativeFree);

/// Loads a null-pointer with a specified type.
///
/// The [nullptr] getter from `dart:ffi` can be slow due to being a
/// `Pointer<Null>` on which the VM has to perform runtime type checks. See also
/// https://github.com/dart-lang/sdk/issues/39488
@pragma('vm:prefer-inline')
Pointer<T> nullPtr<T extends NativeType>() => nullptr.cast<T>();

extension FreePointerExtension on Pointer {
  void free() => allocate.free(this);
}

Pointer<Uint8> allocateBytes(List<int> bytes, {int additionalLength = 0}) {
  final ptr = allocate<Uint8>(bytes.length + additionalLength);

  ptr.asTypedList(bytes.length + additionalLength)
    ..setAll(0, bytes)
    ..fillRange(bytes.length, bytes.length + additionalLength, 0);

  return ptr;
}

/// Allocates bytes, returning `uint8_t*` pointer an a [Uint8List] backed by
/// that memory region.
///
/// When the returned [Uint8List] is no longer referenced in Dart, the memory
/// region will be freed.
(Pointer<Uint8>, Uint8List) allocateBytesWithFinalizer(List<int> bytes) {
  final ptr = allocateBytes(bytes);
  return (ptr, ptr.asTypedList(bytes.length, finalizer: allocate.nativeFree));
}

extension Utf8Utils on Pointer<sqlite3_char> {
  int get _length {
    final asBytes = cast<Uint8>();
    var length = 0;

    for (; asBytes[length] != 0; length++) {}
    return length;
  }

  String? readNullableString([int? length]) {
    return isNullPointer ? null : readString(length);
  }

  String readString([int? length]) {
    final resolvedLength = length ??= _length;
    final dartList = cast<Uint8>().asTypedList(resolvedLength);

    return utf8.decode(dartList);
  }

  static Pointer<sqlite3_char> allocateZeroTerminated(String string) {
    return allocateBytes(utf8.encode(string), additionalLength: 1).cast();
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
