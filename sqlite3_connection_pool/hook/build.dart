import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) {
  return build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    output.assets.code.add(
      CodeAsset(
        package: 'sqlite3_connection_pool',
        name: 'sqlite3_connection_pool.dart',
        linkMode: DynamicLoadingBundled(),
        file: File(
          '/Users/simon/src/sqlite3.dart/sqlite3_connection_pool/target/debug/libsqlite3_connection_pool.dylib',
        ).uri,
      ),
    );
  });
}
