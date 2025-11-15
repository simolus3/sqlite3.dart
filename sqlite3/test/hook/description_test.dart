@Tags(['ffi'])
library;

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import '../../hook/build.dart' as hook;

void main() {
  test('system with custom name', () async {
    await testBuildHook(
      userDefines: PackageUserDefines(
        workspacePubspec: PackageUserDefinesSource(
          defines: {'source': 'system', 'name': 'sqlcipher'},
          basePath: Uri.file(d.sandbox),
        ),
      ),
      mainMethod: hook.main,
      check: (input, output) {
        expect(output.assets.code, [
          isA<CodeAsset>().having(
            (e) => e.linkMode,
            'linkMode',
            DynamicLoadingSystem(Uri.parse('sqlcipher.dll')),
          ),
        ]);
      },
      extensions: [
        CodeAssetExtension(
          targetArchitecture: Architecture.arm64,
          targetOS: OS.windows,
          linkModePreference: LinkModePreference.dynamic,
        ),
      ],
    );
  });
}
