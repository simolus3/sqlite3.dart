import 'dart:convert';
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
import 'package:webdriver/async_io.dart';
import 'package:sqlite3_web/src/types.dart';
import 'package:webdriver/support/async.dart';

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
    final packageConfig =
        await loadPackageConfigUri((await Isolate.packageConfig)!);
    final ownPackage = packageConfig['sqlite3_web']!.root;
    var packageDir = ownPackage.toFilePath(windows: Platform.isWindows);
    if (packageDir.endsWith('/')) {
      packageDir = packageDir.substring(0, packageDir.length - 1);
    }

    final buildRunner = await BuildDaemonClient.connect(
      packageDir,
      [
        Platform.executable, // dart
        'run',
        'build_runner',
        'daemon',
      ],
      logHandler: (log) => print(log.message),
    );

    buildRunner
      ..registerBuildTarget(DefaultBuildTarget((b) => b.target = 'web'))
      ..startBuild();

    // Wait for the build to complete, so that the server we return is ready to
    // go.
    await buildRunner.buildResults.firstWhere((b) {
      final buildResult = b.results.firstWhereOrNull((r) => r.target == 'web');
      return buildResult != null && buildResult.status != BuildStatus.started;
    });

    final assetServerPortFile =
        File(p.join(daemonWorkspace(packageDir), '.asset_server_port'));
    final assetServerPort = int.parse(await assetServerPortFile.readAsString());

    final server = TestAssetServer(buildRunner);

    final proxy = proxyHandler('http://localhost:$assetServerPort/web/');
    server.server = await serve(
      (request) async {
        final pathSegments = request.url.pathSegments;

        if (pathSegments.isNotEmpty && pathSegments[0] == 'no-coep') {
          // Serve stuff under /no-coep like the regular website, but without
          // adding the security headers.
          return await proxy(request.change(path: 'no-coep'));
        } else {
          final response = await proxy(request);

          if (!request.url.path.startsWith('/no-coep')) {
            return response.change(headers: {
              // Needed for shared array buffers to work
              'Cross-Origin-Opener-Policy': 'same-origin',
              'Cross-Origin-Embedder-Policy': 'require-corp'
            });
          }

          return response;
        }
      },
      'localhost',
      8080,
    );

    return server;
  }
}

class TestWebDriver {
  final TestAssetServer server;
  final WebDriver driver;

  TestWebDriver(this.server, this.driver);

  /// Wait for the Dart code on the test page to finish its main method, which
  /// it signals by creating an element.
  Future<void> waitReady() async {
    await waitFor(() => driver.findElement(By.id('ready')));
  }

  Future<bool> isDart2wasm() async {
    return await driver.executeAsync('isDart2wasm("", arguments[0])', []);
  }

  Future<
      ({
        Set<(StorageMode, AccessMode)> impls,
        Set<MissingBrowserFeature> missingFeatures,
        List<ExistingDatabase> existing,
      })> probeImplementations() async {
    final rawResult = await driver
        .executeAsync('detectImplementations("", arguments[0])', []);
    final result = json.decode(rawResult);

    return (
      impls: {
        for (final entry in result['impls'])
          (
            StorageMode.values.byName(entry[0] as String),
            AccessMode.values.byName(entry[1] as String),
          )
      },
      missingFeatures: {
        for (final entry in result['missing'])
          MissingBrowserFeature.values.byName(entry)
      },
      existing: <ExistingDatabase>[
        for (final entry in result['existing'])
          (
            StorageMode.values.byName(entry[0] as String),
            entry[1] as String,
          ),
      ],
    );
  }

  Future<(StorageMode, AccessMode)> openDatabase({
    (StorageMode, AccessMode)? implementation,
    bool onlyOpenVfs = false,
  }) async {
    final desc = switch (implementation) {
      null => null,
      (var storage, var access) => '${storage.name}:${access.name}'
    };

    final method = onlyOpenVfs ? 'open_only_vfs' : 'open';
    final res = await driver
        .executeAsync('$method(arguments[0], arguments[1])', [desc]) as String?;

    // This returns the storage/access mode actually chosen.
    final split = res!.split(':');

    return (
      StorageMode.values.byName(split[0]),
      AccessMode.values.byName(split[1])
    );
  }

  Future<void> closeDatabase() async {
    await driver.executeAsync("close('', arguments[0])", []);
  }

  Future<({int updates, int commits, int rollbacks})> countEvents() async {
    final result =
        await driver.executeAsync('get_updates("", arguments[0])', []);
    return (
      updates: result[0] as int,
      commits: result[1] as int,
      rollbacks: result[2] as int,
    );
  }

  Future<void> execute(String sql) async {
    await driver.executeAsync('exec(arguments[0], arguments[1])', [sql]);
  }

  Future<void> testSecond() async {
    final res = await driver.executeAsync('test_second("", arguments[0])', []);
    if (res != true) {
      throw 'test_second failed! More information may be available in the console.';
    }
  }

  Future<int?> assertFile(bool shouldExist) async {
    final res = await driver.executeAsync(
        'assert_file(arguments[0], arguments[1])', [shouldExist.toString()]);
    res!;

    if (res == false) {
      throw 'assertFile failed! Expected $shouldExist, match return was $res';
    }

    if (res is int) {
      return res;
    } else {
      return null;
    }
  }

  Future<void> flush() async {
    final result = await driver.executeAsync('flush("", arguments[0])', []);
    if (result != true) {
      throw 'flush() failed: $result';
    }
  }

  Future<void> checkReadWrite() async {
    final result =
        await driver.executeAsync('check_read_write("", arguments[0])', []);
    if (result != null) {
      throw 'check_read_write() failed: $result';
    }
  }

  Future<void> delete(StorageMode mode) async {
    await driver
        .executeAsync('delete_db(arguments[0], arguments[1])', [mode.name]);
  }
}
