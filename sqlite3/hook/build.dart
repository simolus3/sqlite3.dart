import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;

import 'package:sqlite3/src/hook/description.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final sqlite = SqliteBinary.forBuild(input);
    switch (sqlite) {
      case PrecompiledBinary():
        final library = sqlite.resolveLibrary(input.config.code);
        library.checkSupported();

        final dir = Directory(
          input.outputDirectoryShared.resolve(library.dirname).toFilePath(),
        );
        if (!dir.existsSync()) {
          dir.createSync();
        }

        final target = File(p.join(dir.path, library.filename));
        final tmp = File('${target.path}.tmp');

        await sqlite
            .fetch(input, output, library)
            .cast<List<int>>()
            .pipe(tmp.openWrite());
        tmp.renameSync(target.path);

        output.assets.code.add(
          CodeAsset(
            package: package,
            name: name,
            linkMode: DynamicLoadingBundled(),
            file: target.uri,
          ),
        );
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
