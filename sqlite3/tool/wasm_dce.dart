import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/src/dart/ast/ast.dart';

void main(List<String> args) async {
  if (args.length != 2) {
    print(
        'Removes elements from a WASM file that are not accessed by the Dart bindings.');
    print('Usage: dart run tool/wasm_dce.dart in.wasm out.wasm');
    exit(1);
  }

  final file = File('lib/src/wasm/wasm_interop.dart');
  final ast = parseString(content: file.readAsStringSync(), path: file.path);

  final finder = _FindUsedSymbols();
  ast.unit.accept(finder);

  final list = File('.dart_tool/used_wasm_symbols.json');
  list.writeAsStringSync(json.encode([
    for (final entry in finder.symbols)
      {
        'name': '_$entry',
        'export': entry,
        'root': true,
      }
  ]));

  final process = await Process.start(
    'wasm-metadce',
    [
      args[0],
      '--graph-file=${list.path}',
      '--output',
      args[1],
    ],
    mode: ProcessStartMode.inheritStdio,
  );
  exit(await process.exitCode);
}

class _FindUsedSymbols extends RecursiveAstVisitor<void> {
  final List<String> symbols = [];
  bool _inInitializer = false;

  _FindUsedSymbols();

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    _inInitializer = true;
    super.visitConstructorFieldInitializer(node);
    _inInitializer = false;
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (_inInitializer) {
      symbols.add(node.value);
    }
  }
}
