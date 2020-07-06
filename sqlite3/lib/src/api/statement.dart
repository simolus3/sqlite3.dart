import 'result_set.dart';

/// A prepared statement.
abstract class PreparedStatement {
  /// Returns the amount of parameters in this prepared statement.
  int get parameterCount;

  /// If this statement contains parameters and [parameters] is too short, an
  /// exception will be thrown.
  void execute([List<Object> parameters = const <Object>[]]);

  /// If this statement contains parameters and [parameters] is too short, an
  /// exception will be thrown.
  ResultSet select([List<Object> parameters = const <Object>[]]);

  /// Disposes this statement and releases associated memory.
  void dispose();
}
