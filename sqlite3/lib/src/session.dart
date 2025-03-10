import 'dart:typed_data';

abstract interface class CommonSession {
  void attach([String? name]);
  Uint8List changeset();
  Uint8List patchset();
  void delete();
}

abstract interface class CommonChangesetIterator {
  //
}