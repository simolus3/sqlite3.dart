import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../types.dart';

final class CompatibilityResult {
  final List<ExistingDatabase> existingDatabases;

  // Fields set when a shared worker replies.

  /// Whether shared workers are allowed to spawn dedicated workers.
  ///
  /// As far as the web standard goes, they're supposed to. It allows us to
  /// spawn a dedicated worker using OPFS in the context of a shared worker,
  /// which is a very reliable storage implementation. Sadly, only Firefox has
  /// implemented this feature.
  final bool sharedCanSpawnDedicated;

  /// Whether dedicated workers can use OPFS.
  ///
  /// The file system API is only available in dedicated workers, so if they
  /// can't use it, the browser just likely doesn't support that API.
  final bool canUseOpfs;

  /// Whether dedicated workers can use the proposed [New FS locking scheme](https://github.com/whatwg/fs/blob/main/proposals/MultipleReadersWriters.md#modes-of-creating-a-filesystemsyncaccesshandle).
  ///
  /// While this is not a standardized web API yet, it is supported in Chrome
  /// and enables a more efficient way to host databases. So, we want to check
  /// for it.
  final bool opfsSupportsReadWriteUnsafe;

  /// Whether IndexedDB is available to shared workers.
  ///
  /// On some browsers, IndexedDB is not available in private/incognito tabs.
  final bool canUseIndexedDb;

  /// Whether dedicated workers can use shared array buffers and the atomics
  /// API.
  ///
  /// This is required for the synchronous channel used to host an OPFS
  /// filesystem between threads. However, it is only available when the page is
  /// served with special headers for security purposes.
  final bool supportsSharedArrayBuffers;

  /// Whether dedicated workers can spawn their own dedicated workers.
  ///
  /// We need two dedicated workers with a synchronous channel between them to
  /// host an OPFS filesystem.
  final bool dedicatedWorkersCanNest;

  CompatibilityResult({
    required this.existingDatabases,
    required this.sharedCanSpawnDedicated,
    required this.canUseOpfs,
    required this.opfsSupportsReadWriteUnsafe,
    required this.canUseIndexedDb,
    required this.supportsSharedArrayBuffers,
    required this.dedicatedWorkersCanNest,
  });

  factory CompatibilityResult.fromJS(JSObject result) {
    final existing = <ExistingDatabase>[];

    final encodedExisting = (result['a'] as JSArray<JSString>).toDart;
    for (var i = 0; i < encodedExisting.length / 2; i++) {
      final mode = StorageMode.values.byName(encodedExisting[i * 2].toDart);
      final name = encodedExisting[i * 2 + 1].toDart;

      existing.add((mode, name));
    }

    return CompatibilityResult(
      existingDatabases: existing,
      sharedCanSpawnDedicated: (result['b'] as JSBoolean).toDart,
      canUseOpfs: (result['c'] as JSBoolean).toDart,
      canUseIndexedDb: (result['d'] as JSBoolean).toDart,
      supportsSharedArrayBuffers: (result['e'] as JSBoolean).toDart,
      dedicatedWorkersCanNest: (result['f'] as JSBoolean).toDart,
      opfsSupportsReadWriteUnsafe: (result['g'] as JSBoolean).toDart,
    );
  }

  JSObject get toJS {
    final encodedDatabases = <JSString>[
      for (final existing in existingDatabases) ...[
        existing.$1.name.toJS,
        existing.$2.toJS,
      ],
    ];

    return JSObject()
      ..['a'] = encodedDatabases.toJS
      ..['b'] = sharedCanSpawnDedicated.toJS
      ..['c'] = canUseOpfs.toJS
      ..['d'] = canUseIndexedDb.toJS
      ..['e'] = supportsSharedArrayBuffers.toJS
      ..['f'] = dedicatedWorkersCanNest.toJS
      ..['g'] = opfsSupportsReadWriteUnsafe.toJS;
  }
}
