import 'package:hooks/hooks.dart';
import 'package:sqlite3_native_assets/src/build.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final build = SqliteBuild(input, output);
    await build.runBuild();
  });
}
