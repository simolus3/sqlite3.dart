import 'dart:io';
import 'dart:isolate';

import 'package:build_daemon/client.dart';
import 'package:build_daemon/constants.dart';
import 'package:build_daemon/data/build_status.dart';
import 'package:build_daemon/data/build_target.dart';
import 'package:collection/collection.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf_io.dart';
import 'package:shelf_proxy/shelf_proxy.dart';

/// Serves example/web under localhost.
void main() async {
  await TestAssetServer.start();
  print('Serving on http://localhost:8080/');
}

class TestAssetServer {
  final BuildDaemonClient buildRunner;
  late final HttpServer server;

  TestAssetServer(this.buildRunner);

  Future<void> close() async {
    await server.close(force: true);
    await buildRunner.close();
  }

  static Future<TestAssetServer> start() async {
    final packageConfig = await loadPackageConfigUri(
      (await Isolate.packageConfig)!,
    );
    final ownPackage = packageConfig['sqlite3']!.root;
    var packageDir = ownPackage.toFilePath(windows: Platform.isWindows);
    if (packageDir.endsWith('/')) {
      packageDir = packageDir.substring(0, packageDir.length - 1);
    }

    final buildRunner = await BuildDaemonClient.connect(packageDir, [
      Platform.executable, // dart
      'run',
      'build_runner',
      'daemon',
    ], logHandler: (log) => print(log.message));

    buildRunner
      ..registerBuildTarget(DefaultBuildTarget((b) => b.target = 'example'))
      ..startBuild();

    // Wait for the build to complete, so that the server we return is ready to
    // go.
    await buildRunner.buildResults.firstWhere((b) {
      final buildResult = b.results.firstWhereOrNull(
        (r) => r.target == 'example',
      );
      return buildResult != null && buildResult.status != BuildStatus.started;
    });

    final assetServerPortFile = File(
      p.join(daemonWorkspace(packageDir), '.asset_server_port'),
    );
    final assetServerPort = int.parse(await assetServerPortFile.readAsString());

    final server = TestAssetServer(buildRunner);

    final proxy = proxyHandler(
      'http://localhost:$assetServerPort/example/web/',
    );
    server.server = await serve(proxy, 'localhost', 8080);
    return server;
  }
}
