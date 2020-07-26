# sqlite3.dart

This project contains Dart packages to use SQLite from Dart via `dart:ffi`.

The main package in this repository is [`sqlite3`](sqlite3), which contains all the Dart apis and their implementation.
`package:sqlite3` is a pure-Dart package without a dependency on Flutter. 
In can be used both in Flutter apps or in standalone Dart applications.

The `sqlite3_flutter_libs` and `sqlcipher_flutter_libs` packages contain no Dart code at all. Flutter users can depend
on one of them to include native libraries in their apps.

## Quick Start (pure Dart)

```
final db = sqlite3.openInMemory();

// Create a table.
String createTableStatement = '''
  CREATE TABLE dog (
    dog_id INTEGER PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    breed TEXT NOT NULL
  );
''';
db.execute(createTableStatement);

// Insert a row.
String insertRowStatement = '''
  INSERT INTO dog (name, breed)
  VALUES ("Doggo", "Golden Retriever");
''';
db.execute(insertRowStatement);

// Get rows from table.
ResultSet resultSet = db.select("SELECT * FROM dog;");
print(resultSet);

// Update a row.
String updateRowStatement = '''
  UPDATE dog
  SET name = "Doggie", breed = "Chihuahua"
  WHERE dog_id = 1;
''';
db.execute(updateRowStatement);

resultSet = db.select("SELECT * FROM dog;");
print(resultSet);

// Delete a row.
String deleteRowStatement = '''
  DELETE FROM dog
  WHERE dog_id = 1; 
''';
db.execute(deleteRowStatement);

resultSet = db.select("SELECT * FROM dog;");
print(resultSet);

// Insert multiple rows.
String insertRowsStatement = '''
  INSERT INTO dog (name, breed)
  VALUES
    ("Doggo", "Golden Retriever"),
    ("Doggie", "Chihuahua"),
    ("Doggy", "Dalmatian");
''';
db.execute(insertRowsStatement);

resultSet = db.select("SELECT * FROM dog;");
print(resultSet);

// Use the result set and iterate through the result rows.
Iterator<Row> resultSetIterator = resultSet.iterator;
while (resultSetIterator.moveNext()) {
  Row row = resultSetIterator.current;
  print('Dog Object: [id: ${row['dog_id']}, name: ${row['name']}, breed: ${row['breed']}]');
}

// Close the database.
db.dispose();
```