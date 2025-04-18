@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:sqlite3_web/src/types.dart';
import 'package:test/test.dart';
import 'package:webdriver/async_io.dart';

import '../tool/server.dart';

enum Browser {
  chrome(
    driverUriString: 'http://localhost:4444/wd/hub/',
    isChromium: true,
    unsupportedImplementations: {
      (StorageMode.opfs, AccessMode.throughSharedWorker)
    },
    missingFeatures: {MissingBrowserFeature.dedicatedWorkersInSharedWorkers},
    defaultImplementation: (
      StorageMode.opfs,
      AccessMode.throughDedicatedWorker
    ),
  ),
  firefox(
    driverUriString: 'http://localhost:4444/',
    defaultImplementation: (StorageMode.opfs, AccessMode.throughSharedWorker),
  );

  final bool isChromium;
  final String driverUriString;
  final Set<(StorageMode, AccessMode)> unsupportedImplementations;
  final Set<MissingBrowserFeature> missingFeatures;
  final (StorageMode, AccessMode) defaultImplementation;

  const Browser({
    required this.driverUriString,
    required this.defaultImplementation,
    this.isChromium = false,
    this.unsupportedImplementations = const {},
    this.missingFeatures = const {},
  });

  Uri get driverUri => Uri.parse(driverUriString);

  Set<(StorageMode, AccessMode)> get availableImplementations {
    final available = <(StorageMode, AccessMode)>{};
    for (final storage in StorageMode.values) {
      for (final access in AccessMode.values) {
        if (access == AccessMode.inCurrentContext &&
            storage == StorageMode.opfs) {
          // OPFS access is only available in workers.
          continue;
        }

        if (!unsupportedImplementations.contains((storage, access))) {
          available.add((storage, access));
        }
      }
    }

    return available;
  }

  bool supports((StorageMode, AccessMode) impl) =>
      !unsupportedImplementations.contains(impl);

  Future<Process> spawnDriver() async {
    return switch (this) {
      firefox => Process.start('geckodriver', []).then((result) async {
          // geckodriver seems to take a while to initialize
          await Future.delayed(const Duration(seconds: 1));
          return result;
        }),
      chrome =>
        Process.start('chromedriver', ['--port=4444', '--url-base=/wd/hub']),
    };
  }
}

void main() {
  late TestAssetServer server;

  setUpAll(() async {
    server = await TestAssetServer.start();
  });
  tearDownAll(() => server.close());

  for (final browser in Browser.values) {
    group(browser.name, () {
      late Process driverProcess;
      var isStoppingProcess = false;
      final processStopped = Completer<void>();

      setUpAll(() async {
        final process = driverProcess = await browser.spawnDriver();
        process.exitCode.then((code) {
          if (!isStoppingProcess) {
            throw 'Webdriver stopped (code $code) before tearing down tests.';
          }

          processStopped.complete();
        });
      });
      tearDownAll(() {
        isStoppingProcess = true;
        driverProcess.kill();
        return processStopped.future;
      });

      for (final wasm in [false, true]) {
        group(wasm ? 'dart2wasm' : 'dart2js', () {
          final config = _TestConfiguration(browser, () => server, wasm);

          setUp(() async {
            await config.setUp();
          });
          tearDown(() => config.tearDown());

          config.declareTests();
        });
      }
    });
  }
}

final class _TestConfiguration {
  final Browser browser;
  final TestAssetServer Function() _server;
  final bool isDart2Wasm;

  late TestWebDriver driver;

  _TestConfiguration(this.browser, this._server, this.isDart2Wasm);

  TestAssetServer get server => _server();

  Future<void> setUp() async {
    late WebDriver rawDriver;
    for (var i = 0; i < 3; i++) {
      try {
        rawDriver = await createDriver(
          spec: browser.isChromium ? WebDriverSpec.JsonWire : WebDriverSpec.W3c,
          uri: browser.driverUri,
          desired: {
            'goog:chromeOptions': {
              'args': [
                '--headless=new',
                '--disable-search-engine-choice-screen',
              ],
            },
            'moz:firefoxOptions': {
              'args': ['-headless']
            },
          },
        );
        break;
      } on SocketException {
        // webdriver server taking a bit longer to start up...
        if (i == 2) {
          rethrow;
        }

        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // logs.get() isn't supported on Firefox
    if (browser != Browser.firefox) {
      rawDriver.logs.get(LogType.browser).listen((entry) {
        print('[console]: ${entry.message}');
      });
    }

    driver = TestWebDriver(server, rawDriver);
    await driver.driver.get(isDart2Wasm
        ? 'http://localhost:8080/?wasm=1'
        : 'http://localhost:8080/');
    await driver.waitReady();
  }

  Future<void> tearDown() async {
    await driver.driver.quit();
  }

  void declareTests() {
    test('compatibility check', () async {
      // Make sure we're not testing the same compiler twice due to e.g. bugs in
      // the loader script.
      expect(await driver.isDart2wasm(), isDart2Wasm);

      final result = await driver.probeImplementations();

      expect(result.missingFeatures, browser.missingFeatures);
      expect(result.impls, browser.availableImplementations);
    });

    test('picks recommended option', () async {
      final (storage, access) = await driver.openDatabase();
      expect((storage, access), browser.defaultImplementation);
    });

    for (final (storage, access) in browser.availableImplementations) {
      test('$storage through $access', () async {
        await driver.openDatabase(
          implementation: (storage, access),
          onlyOpenVfs: true,
        );
        await driver.assertFile(false);

        await driver.execute('CREATE TABLE foo (bar TEXT);');
        var events = await driver.countEvents();
        expect(events.updates, 0);
        expect(events.commits, 0);
        expect(events.rollbacks, 0);
        await driver.execute("INSERT INTO foo (bar) VALUES ('hello');");
        events = await driver.countEvents();
        expect(events.updates, 1);
        expect(events.commits, 1);

        expect(await driver.assertFile(true), isPositive);
        await driver.flush();

        await driver.execute('begin');
        await driver.execute('rollback');
        events = await driver.countEvents();
        expect(events.rollbacks, 1);

        if (storage != StorageMode.inMemory) {
          await driver.driver.refresh();
          await driver.waitReady();

          await driver.openDatabase(
            implementation: (storage, access),
            onlyOpenVfs: true,
          );
          await driver.assertFile(true);

          await driver.driver.refresh();
          await driver.waitReady();
          await driver.delete(storage);
          await driver.openDatabase(
            implementation: (storage, access),
            onlyOpenVfs: true,
          );
          await driver.assertFile(false);
        }
      });

      test('check large write and read', () async {
        await driver.openDatabase(
          implementation: (storage, access),
          onlyOpenVfs: true,
        );
        await driver.assertFile(false);

        await driver.checkReadWrite();
      });
    }

    test('can share databases', () async {
      await driver.testSecond();
    });
  }
}
