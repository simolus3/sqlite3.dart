import 'package:custom_extension/sqlite_vec.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    sqlite3.loadSqliteVectorExtension();
  });

  test('can use vec0', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);

    db.execute(
      'create virtual table vec_examples using vec0(sample_embedding float[8])',
    );
  });
}
