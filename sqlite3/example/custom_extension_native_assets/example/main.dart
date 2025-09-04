import 'package:sqlite3_native_assets/sqlite3_native_assets.dart';
import 'package:custom_extension_native_assets/uuid.dart';

void main() {
  final sqlite3 = sqlite3Native;
  sqlite3.loadSqliteVectorExtension();

  final db = sqlite3.openInMemory();
  db.execute('''
create virtual table vec_examples using vec0(
  sample_embedding float[8]
);

insert into vec_examples(rowid, sample_embedding)
  values
    (1, '[-0.200, 0.250, 0.341, -0.211, 0.645, 0.935, -0.316, -0.924]'),
    (2, '[0.443, -0.501, 0.355, -0.771, 0.707, -0.708, -0.185, 0.362]'),
    (3, '[0.716, -0.927, 0.134, 0.052, -0.669, 0.793, -0.634, -0.162]'),
    (4, '[-0.710, 0.330, 0.656, 0.041, -0.990, 0.726, 0.385, -0.958]');
''');

  print(
    db.select('''
select
  rowid,
  distance
from vec_examples
where sample_embedding match '[0.890, 0.544, 0.825, 0.961, 0.358, 0.0196, 0.521, 0.175]'
order by distance
limit 2;
'''),
  );
}
