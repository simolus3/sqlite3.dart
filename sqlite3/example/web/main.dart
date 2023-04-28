import 'dart:html';

Future<void> main() async {
  final worker = Worker('worker.dart.js');
  final startButton = document.getElementById('start')!;
  await startButton.onClick.first;

  startButton.remove();
  worker.postMessage('start');
}
