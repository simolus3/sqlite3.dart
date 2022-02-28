import 'dart:math';

class SqliteEnvironment {
  final Random random;

  SqliteEnvironment({Random? random}) : random = random ?? Random.secure();
}
