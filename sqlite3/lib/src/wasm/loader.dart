import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:meta/meta.dart';

import 'injected_values.dart';

import 'package:web/web.dart' as web;

import 'js_interop.dart';

/// Utility to load `sqlite3.wasm` files.
///
/// This class can be extended to inject additional host functions into loaded
/// modules.
///
/// {@category wasm}
@experimental
base class WasmModuleLoader {
  final _dartFunctions = DartBridgeCallbacks();

  /// Creates a JavaScript object providing definitions used as imported
  /// functions by the WebAssembly module.
  ///
  /// The default build uses the `dart` namespace to import definitions provided
  /// by the `sqlite3` package. Custom builds might need additional functions,
  /// which can be provided by overriding this method to install additional
  /// namespaces.
  JSObject createImportObject() {
    return JSObject()..['dart'] = createJSInteropWrapper(_dartFunctions);
  }

  /// Instantiates a module by calling `WebAssembly.instantiateStreaming`
  /// with the response and [createImportObject].
  Future<JSObject> instantiateModule(web.Response response) {
    return instantiateStreaming(response, createImportObject()).toDart;
  }

  /// Load and instantiate a WebAssembly module from a fetch response by
  /// providing host imports.
  ///
  /// Returns a `WebAssembly.Instance` JavaScript object.
  Future<JSObject> loadModule(web.Response response) async {
    final module = (await instantiateModule(response)) as ResultObject;

    // If the module has an `_initialize` export, it needs to be called to run
    // C constructors and set up memory.
    final exports = module.instance.exports;
    if (exports.has('_initialize')) {
      (exports['_initialize'] as JSFunction).callAsFunction();
    }

    return module.instance;
  }
}

// Hidden in public interface
@internal
extension InternalWasmLoader on WasmModuleLoader {
  DartBridgeCallbacks get dartFunctions => _dartFunctions;
}
