import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.onRecord.listen(print);

  final generator = FfiGenerator(
    output: Output(
      dart: DartOutput(path: Uri.parse('lib/src/ffi.g.dart')),
      preamble: '// ignore_for_file: type=lint',
      style: NativeExternalBindings(
        assetId: 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart',
      ),
    ),
    input: Input(entryPoints: [Uri.parse('src/headers.h')]),
    visitors: [
      Visitor(
        func: (node) {
          node
            ..isIncluded = node.originalName.startsWith(
              'pkg_sqlite3_connection_pool',
            )
            // The obtain functions post completions to a port and don't obtain any
            // locks, so we can mark them as isLeaf.
            ..isLeaf =
                node.originalName.contains('obtain') ||
                node.originalName.contains('stmt_cache')
            // Close functions are used for native finalizers
            ..exposeSymbolAddress = node.originalName.contains('close');
        },
        struct: (s) => s.isIncluded =
            s.originalName == 'InitializedPool' ||
            s.originalName == 'PoolConnection',
      ),
    ],
  );
  generator.generate();
}
