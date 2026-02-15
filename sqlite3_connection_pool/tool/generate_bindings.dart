import 'package:ffigen/ffigen.dart';
import 'package:logging/logging.dart';

void main() {
  Logger.root.onRecord.listen(print);

  final generator = FfiGenerator(
    output: Output(
      dartFile: Uri.parse('lib/src/ffi.g.dart'),
      preamble: '// ignore_for_file: type=lint',
      style: NativeExternalBindings(
        assetId: 'package:sqlite3_connection_pool/sqlite3_connection_pool.dart',
      ),
    ),
    headers: Headers(entryPoints: [Uri.parse('src/headers.h')]),
    functions: Functions(
      include: (d) => d.originalName.startsWith('pkg_sqlite3_connection_pool'),
      // The obtain functions post completions to a port and don't obtain any
      // locks, so we can mark them as isLeaf.
      isLeaf: (d) => d.originalName.contains('obtain'),
      // Close functions are used for native finalizers
      includeSymbolAddress: (d) => d.originalName.contains('close'),
    ),
    structs: Structs(include: (d) => d.originalName == 'InitializedPool'),
  );
  generator.generate();
}
