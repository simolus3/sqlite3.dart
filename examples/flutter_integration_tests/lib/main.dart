import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  runApp(SqliteDiagnostics());
}

class SqliteDiagnostics extends StatelessWidget {
  const SqliteDiagnostics({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(child: const _SqliteDiagnosticText()),
        ),
      ),
    );
  }
}

class _SqliteDiagnosticText extends StatefulWidget {
  const _SqliteDiagnosticText();

  @override
  State<_SqliteDiagnosticText> createState() => _SqliteDiagnosticTextState();
}

class _SqliteDiagnosticTextState extends State<_SqliteDiagnosticText> {
  var _text = 'Loading';

  @override
  void initState() {
    super.initState();

    final db = sqlite3.openInMemory();
    final options = db.select('pragma compile_options');
    setState(() {
      _text = 'Version: ${sqlite3.version}\nOptions: $options';
    });
    db.close();
  }

  @override
  Widget build(BuildContext context) {
    return Text(_text);
  }
}
