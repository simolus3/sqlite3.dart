import 'dart:js_interop';

enum FileSystemImplementation {
  opfsShared('s'),
  opfsAtomics('l'),
  opfsExternalLocks('x'),
  indexedDb('i'),
  inMemory('m');

  final String jsRepresentation;

  const FileSystemImplementation(this.jsRepresentation);

  JSString get toJS => jsRepresentation.toJS;

  bool get needsExternalLocks =>
      // Technically, opfsAtomics doesn't need external locks around each
      // database access. We just do this to avoid contention in the underlying
      // VFS.
      this == opfsAtomics || this == opfsExternalLocks;

  static FileSystemImplementation fromJS(JSString js) {
    final toDart = js.toDart;

    for (final entry in values) {
      if (entry.jsRepresentation == toDart) return entry;
    }

    throw ArgumentError('Unknown FS implementation: $toDart');
  }
}
