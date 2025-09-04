import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:http/http.dart';
import 'package:tar/tar.dart';

void main(List<String> args) {
  build(args, (input, output) async {
    final targetOS = input.config.code.targetOS;
    final arch = input.config.code.targetArchitecture;

    final (osName, fileName) = switch (targetOS) {
      OS.linux => ('linux', 'vec0.so'),
      OS.macOS => ('macos', 'vec0.dylib'),
      OS.windows => ('windows', 'vec0.dll'),
      _ => throw UnsupportedError('Unsupported target os $targetOS'),
    };
    final archName = switch (arch) {
      Architecture.x64 => 'x86_64',
      Architecture.arm64 => 'aarch64',
      _ => throw UnsupportedError('Unsupported target architecture $arch'),
    };

    final client = Client();
    final uri = Uri.parse(
      'https://github.com/asg017/sqlite-vec/releases/download/v$version/sqlite-vec-$version-loadable-$osName-$archName.tar.gz',
    );
    final response = await client.send(
      Request('GET', uri)..followRedirects = true,
    );
    if (response.statusCode != 200) {
      throw StateError(
        'Unexpected status code ${response.statusCode} for $uri',
      );
    }

    final reader = TarReader(response.stream.transform(gzip.decoder));
    var foundFile = false;
    while (await reader.moveNext()) {
      final current = reader.current;
      if (current.name == fileName) {
        final targetFilePath = input.outputDirectory.resolve(fileName);
        final targetFile = File(targetFilePath.path);
        await current.contents.pipe(targetFile.openWrite());

        output.assets.code.add(
          CodeAsset(
            package: 'custom_extension_native_assets',
            name: 'uuid.dart',
            file: targetFilePath,
            linkMode: DynamicLoadingBundled(),
          ),
        );

        foundFile = true;
        break;
      }
    }

    if (!foundFile) {
      throw 'Could not find $fileName in $uri';
    }

    await reader.cancel();
    client.close();
  });
}

const version = '0.1.6';
