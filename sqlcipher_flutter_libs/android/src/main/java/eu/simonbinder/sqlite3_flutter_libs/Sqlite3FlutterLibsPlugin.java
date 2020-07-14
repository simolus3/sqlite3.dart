package eu.simonbinder.sqlite3_flutter_libs;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/** Sqlite3FlutterLibsPlugin */
public class Sqlite3FlutterLibsPlugin implements FlutterPlugin {

  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    // Do nothing, we only need the native libraries.
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    // Again, nothing to do here.
  }

}
