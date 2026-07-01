import 'dart:collection';

import 'package:sqlite3/wasm.dart';

/// A cached of prepared statements, used by workers to avoid having to prepare
/// SQL statements multiple times when they're used frequently.
final class PreparedStatementCache {
  /// The maximum amount of statements to cache.
  final int size;

  // The linked map returns entries in the order in which they have been
  // inserted (with the first insertion being reported first).
  // So, we treat it as a LRU cache with `entries.last` being the MRU and
  // `entries.first` being the LRU element.
  final LinkedHashMap<String, CommonPreparedStatement> _cachedStatements =
      LinkedHashMap();

  PreparedStatementCache({required this.size}) : assert(size > 0);

  /// Attempts to look up the cached [sql] statement, if it exists.
  ///
  /// If the statement exists, it is marked as most recently used as well.
  CommonPreparedStatement? use(String sql) {
    // Remove and add the statement if it was found to move it to the end,
    // which marks it as the MRU element.
    final foundStatement = _cachedStatements.remove(sql);

    if (foundStatement != null) {
      _cachedStatements[sql] = foundStatement;
    }

    return foundStatement;
  }

  /// Caches a statement that has not been cached yet for subsequent uses.
  void addNew(CommonPreparedStatement statement) {
    assert(!_cachedStatements.containsKey(statement.sql));

    if (_cachedStatements.length == size) {
      final lru = _cachedStatements.remove(_cachedStatements.keys.first)!;
      lru.close();
    }

    _cachedStatements[statement.sql] = statement;
  }

  /// Removes all cached statements.
  void disposeAll() {
    for (final statement in _cachedStatements.values) {
      statement.close();
    }

    _cachedStatements.clear();
  }
}
