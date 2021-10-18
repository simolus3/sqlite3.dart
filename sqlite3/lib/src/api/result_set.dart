import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Base class for result sets that are either an in-memory ([ResultSet]) or
/// a lazy iterator ([IteratingCursor]).
@sealed
abstract class Cursor {
  /// The column names of this query, as returned by `sqlite3`.
  final List<String> columnNames;

  /// The table names of this query, as returned by `sqlite3`.
  ///
  /// A table name is null when the column is not directly associated
  /// with a table, such as a computed column.
  /// The list is null if the sqlite library was not compiled with the SQLITE_ENABLE_COLUMN_METADATA
  /// C-preprocessor symbol.
  /// More information in https://www.sqlite.org/c3ref/column_database_name.html.
  final List<String?>? tableNames;
  // a result set can have multiple columns with the same name, but that's rare
  // and users usually use a name as index. So we cache that for O(1) lookups
  final Map<String, int> _calculatedIndexes;

  Cursor(this.columnNames, this.tableNames)
      : _calculatedIndexes = {
          for (var column in columnNames)
            column: columnNames.lastIndexOf(column),
        };
}

/// A [Cursor] that can only be read once, obtaining rows from the database as
/// necessary.
abstract class IteratingCursor extends Cursor implements Iterator<Row> {
  IteratingCursor(List<String> columnNames, List<String?>? tableNames)
      : super(columnNames, tableNames);
}

/// Stores the full result of a select statement.
class ResultSet extends Cursor
    with IterableMixin<Row>
    implements Iterable<Row> {
  /// The raw row data.
  final List<List<Object?>> rows;

  ResultSet(List<String> columnNames, List<String?>? tableNames, this.rows)
      : super(columnNames, tableNames);

  @override
  Iterator<Row> get iterator => _ResultIterator(this);
}

/// A single row in the result of a select statement.
///
/// This class implements the [Map] interface, which can be used to look up the
/// value of a column by its name.
/// The [columnAt] method may be used to obtain the value of a column by its
/// index.
class Row
    with UnmodifiableMapMixin<String, dynamic>, MapMixin<String, dynamic>
    implements Map<String, dynamic> {
  final Cursor _result;
  final List<Object?> _data;

  Row(this._result, this._data);

  /// Returns the value stored in the [i]-th column in this row (zero-indexed).
  dynamic columnAt(int i) {
    return _data[i];
  }

  @override
  dynamic operator [](Object? key) {
    if (key is! String) return null;

    final index = _result._calculatedIndexes[key];
    if (index == null) return null;

    return columnAt(index);
  }

  @override
  Iterable<String> get keys => _result.columnNames;

  /// Returns a two-level map that on the first level contains the resolved
  /// non-aliased table name, and on the second level the column name (or its alias).
  ///
  /// A table name (first level map key) is null when the column is not directly associated
  /// with a table, such as a computed column.
  /// The map is null if the sqlite3 library was not compiled with the SQLITE_ENABLE_COLUMN_METADATA
  /// C-preprocessor symbol.
  /// More information in https://www.sqlite.org/c3ref/column_database_name.html.
  Map<String?, Map<String, dynamic>>? toTableColumnMap() {
    if (_result.tableNames == null) {
      return null;
    }
    final Map<String?, Map<String, dynamic>> map = {};
    for (int i = 0; i < _data.length; i++) {
      final tableName = _result.tableNames![i];
      final columnName = _result.columnNames[i];
      final value = _data[i];

      final columnsMap = map.putIfAbsent(tableName, () => <String, dynamic>{});
      columnsMap[columnName] = value;
    }
    return map;
  }
}

class _ResultIterator extends Iterator<Row> {
  final ResultSet result;
  int index = -1;

  _ResultIterator(this.result);

  @override
  Row get current => Row(result, result.rows[index]);

  @override
  bool moveNext() {
    index++;
    return index < result.rows.length;
  }
}
