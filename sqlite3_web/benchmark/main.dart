import 'package:async/async.dart';
import 'package:jaspr/client.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr_riverpod/jaspr_riverpod.dart';
import 'package:sqlite3_web/sqlite3_web.dart';

import 'benchmark.dart';

/// To run benchmarks: `webdev serve benchmark:8080 --release`, also copy a
/// `sqlite3.wasm` into this directory.
void main() {
  runApp(const ProviderScope(child: BenchmarkApp()), attachTo: '#app');
}

final class BenchmarkApp extends StatelessComponent {
  const BenchmarkApp();

  @override
  Component build(BuildContext context) {
    final detectedFeatures = context.watch(featureDetectionResult);
    final clientState = context.watch(ClientStateNotifier.provider);

    switch (detectedFeatures) {
      case AsyncLoading<FeatureDetectionResult>():
        return Component.text('Initializing...');
      case AsyncData<FeatureDetectionResult>(:final value):
        return Component.fragment([
          Component.text(
            'Tab is ready (${clientState?.tabIdPlusOne} / ${clientState?.numTabs} tabs). Select benchmark to run',
          ),
          _BenchmarkSelector(value),
          const _BenchmarkResults(),
        ]);

      case AsyncError<FeatureDetectionResult>(:final error):
        return Component.text('Error initializing: $error');
    }
  }
}

final class _BenchmarkSelector extends StatelessComponent {
  final FeatureDetectionResult _features;

  _BenchmarkSelector(this._features);

  @override
  Component build(BuildContext context) {
    final currentSelection = context.watch(selectedTarget);

    return div([
      select(
        value: switch (currentSelection) {
          SingleTabBenchmarkTarget() => 'single',
          MultiTabBenchmarkTarget() => 'multi',
        },
        onChange: (value) {
          context.read(selectedTarget.notifier).state = switch (value) {
            ['multi'] => MultiTabBenchmarkTarget(
              BenchmarkConfiguration.defaultConfig,
            ),
            _ => SingleTabBenchmarkTarget(BenchmarkConfiguration.defaultConfig),
          };
        },
        [
          const option(value: 'single', [Component.text('Single-tab')]),
          const option(value: 'multi', [Component.text('Multi tab')]),
        ],
      ),
      select(
        value: currentSelection.configuration.implementation.name,
        onChange: (value) {
          final implementation = DatabaseImplementation.values.byName(value[0]);

          context.read(selectedTarget.notifier).state = currentSelection
              .changeConfig(
                BenchmarkConfiguration(implementation: implementation),
              );
        },
        [
          for (final available in _features.availableImplementations)
            option(value: available.name, [Component.text(available.name)]),
        ],
      ),
      button(
        onClick: () {
          final loadedSqlite = context.read(sqlite3);
          final target = context.read(selectedTarget);

          switch (target) {
            case SingleTabBenchmarkTarget():
              context
                  .read(BenchmarkState.provider.notifier)
                  .runSingleTabBenchmarks(target, loadedSqlite);
            case MultiTabBenchmarkTarget():
              // TODO: Handle this case.
              throw UnimplementedError();
          }
        },
        disabled: false,
        [Component.text('Run!')],
      ),
    ]);
  }
}

final class _BenchmarkResults extends StatelessComponent {
  const _BenchmarkResults();

  @override
  Component build(BuildContext context) {
    final results = context.watch(BenchmarkState.provider);

    return div([
      const h2([Component.text('Results')]),
      if (results case ValueResult(value: final results))
        ol([
          for (final result in results)
            li(key: ValueKey(result), [Component.text(result.description)]),
        ]),

      if (results.asError case final error?)
        pre([
          code([
            Component.text(error.error.toString()),
            const br(),
            Component.text(error.stackTrace.toString()),
          ]),
        ]),
    ]);
  }
}
