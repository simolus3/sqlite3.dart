import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:sqlite3/src/hook/description.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final sqlite = SqliteBinary.forBuild(input);
    if (sqlite case final CompileSqlite compile) {
      throw 'todo: $compile';
    }

    switch (sqlite) {
      case PrecompiledFromGithubAssets():
        // TODO: Handle this case.
        throw UnimplementedError();
      case PrecompiledForTesting():
        // TODO: Handle this case.
        throw UnimplementedError();
      case CompileSqlite():
        // TODO: Handle this case.
        throw UnimplementedError();
      case SimpleBinary():
        output.assets.code.add(
          CodeAsset(
            package: package,
            name: name,
            linkMode: sqlite.resolveLinkMode(input),
          ),
        );
    }
  });
}

const package = 'sqlite3';
const name = 'src/ffi/libsqlite3.g.dart';
