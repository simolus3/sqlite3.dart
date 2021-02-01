import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as ffi;

import 'sqlite3.ffi.dart';

const allocate = ffi.malloc;

/// Loads a null-pointer with a specified type.
///
/// The [nullptr] getter from `dart:ffi` can be slow due to being a
/// `Pointer<Null>` on which the VM has to perform runtime type checks. See also
/// https://github.com/dart-lang/sdk/issues/39488
@pragma('vm:prefer-inline')
Pointer<T> nullPtr<T extends NativeType>() => nullptr.cast<T>();

Pointer<Void> _freeImpl(Pointer<Void> ptr) {
  ptr.free();
  return nullPtr();
}

/// Pointer to a function that frees memory we allocated.
///
/// This corresponds to `void(*)(void*)` arguments found in sqlite.
final Pointer<NativeFunction<Pointer<Void> Function(Pointer<Void>)>>
    freeFunctionPtr = Pointer.fromFunction(_freeImpl);

extension FreePointerExtension on Pointer {
  void free() => allocate.free(this);
}

Pointer<Uint8> allocateBytes(List<int> bytes, {int additionalLength = 0}) {
  final ptr = allocate.allocate<Uint8>(bytes.length + additionalLength);

  final data = Uint8List(bytes.length + additionalLength)..setAll(0, bytes);
  ptr.asTypedList(bytes.length + additionalLength).setAll(0, data);

  return ptr;
}

Pointer<char> allocateZeroTerminated(String string) {
  return allocateBytes(utf8.encode(string), additionalLength: 1).cast();
}
