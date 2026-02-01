import 'dart:js_interop';

enum ToWorkerMessageType { sqlite, connectTab }

enum ToClientMessageType { tabId }

extension type WorkerMessage._(JSObject _) implements JSObject {
  external factory WorkerMessage({
    required String type,
    required JSAny? payload,
  });

  external String get type;
  external JSAny? get payload;
}

extension type ConnectTab._(JSObject _) implements JSObject {
  /// A lock obtained by the connecting tab.
  ///
  /// The shared worker will attempt to also obtain this lock, and can know that
  /// the tab has closed once that succeeds.
  external String get lockName;

  external factory ConnectTab({required String lockName});
}

extension type ReceiveTabId._(JSObject _) implements JSObject {
  external factory ReceiveTabId({
    required JSNumber index,
    required JSNumber numTabs,
  });

  external JSNumber get index;
  external JSNumber get numTabs;
}
