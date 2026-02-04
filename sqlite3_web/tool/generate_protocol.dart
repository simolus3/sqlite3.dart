void main() {
  final gen = SourceGenerator()..write(ProtocolMessageType.openRequest);

  print(gen);
}

final class SourceGenerator {
  final StringBuffer imports = StringBuffer();
  final StringBuffer commons = StringBuffer();
  final StringBuffer content = StringBuffer();

  final Set<ProtocolMessageType> _writtenTypes = {};

  void write(ProtocolMessageType type) {
    if (type.parent case final parent?) {
      write(parent);
    }

    if (!_writtenTypes.add(type)) {
      return;
    }

    final parentName = type.parent?.name ?? 'JSObject';

    content.writeln(
      'extension type ${type.name}($parentName _) implements $parentName {',
    );

    for (final field in type.fields) {
      writeFieldDefinition(field);
    }

    content.writeln();
    if (!type.isAbstract) {
      // Private private literal constructor
      final usedNames = <String, FieldConstructorInfo>{};
      content.writeln('  external factory ${type.name}._({');
      _writeLiteralConstructorParameters(type, type, usedNames);
      content.writeln('  });');

      // Public factory filling in defaults
      content.writeln('  factory ${type.name}({');
      for (final value in usedNames.values) {
        if (value.fixedValue == null) {
          content.writeln('    required ${value.type} ${value.dartName},');
        }
      }
      content
        ..writeln('  }) {')
        ..writeln('    return ${type.name}._(');

      for (final value in usedNames.values) {
        if (value.fixedValue case final fixed?) {
          content.writeln('      ${value.dartName}: $fixed,');
        } else {
          content.writeln(
            '      ${value.dartName}: ${value.fieldType!.dartToRepr(value.dartName)},',
          );
        }
      }

      content
        ..writeln('    );')
        ..writeln('  }');
    }

    content.writeln('}');
  }

  void _writeLiteralConstructorParameters(
    ProtocolMessageType original,
    ProtocolMessageType type,
    Map<String, FieldConstructorInfo> usedNames,
  ) {
    for (final field in type.fields) {
      if (usedNames.containsKey(field.protocolName) && field.nullable) {
        continue; // Overridden in subtype
      } else if (usedNames.containsKey(field.protocolName)) {
        throw ArgumentError('Duplicate field name');
      }

      content
        ..write("    @JS('${field.protocolName}')")
        ..write(field.nullable ? ' ' : ' required ')
        ..writeln('${field.type.representationType} ${field.name},');

      usedNames[field.protocolName] = FieldConstructorInfo(
        field.type.dartType,
        field.name,
        null,
        field.type,
      );
    }

    if (type.parent case final parent?) {
      _writeLiteralConstructorParameters(original, parent, usedNames);
    }

    if (type == ProtocolMessageType.message) {
      content.writeln(
        "    @JS('${_UniqueFieldNames.type}') required String get type",
      );
      usedNames[_UniqueFieldNames.type] = FieldConstructorInfo(
        'MessageType',
        'type',
        'MessageType.${original.enumTypeName}.name',
      );
    }
  }

  void writeFieldDefinition(ProtocolMessageField field) {
    content
      ..write("  @JS('${field.protocolName}')")
      ..write('external ${field.type.representationType}')
      ..write(field.type.needsWrapper ? ' _' : ' ')
      ..write(field.name)
      ..writeln(';');

    if (field.type.needsWrapper) {
      switch (field.type) {
        case FieldType.uri:
          content.writeln(
            '  Uri get ${field.name} => Uri.parse(_${field.name});',
          );
          content.writeln(
            '  set ${field.name}(Uri uri) => _${field.name} = ${field.type.dartToRepr('uri')};',
          );
        case FieldType.fileSystemImplementation:
          content.writeln(
            '  FileSystemImplementation get ${field.name} => FileSystemImplementation.fromName(_${field.name});',
          );
          content.writeln(
            '  set ${field.name}(FileSystemImplementation impl) => _${field.name} = ${field.type.dartToRepr('impl')}',
          );
        default:
          throw AssertionError();
      }
    }
  }

  @override
  String toString() {
    return '$imports\n$commons\n$content';
  }
}

final class ProtocolMessageType {
  final String name;
  final List<ProtocolMessageField> fields = [];

  bool isAbstract = false;
  ProtocolMessageType? _parent;
  final List<ProtocolMessageType> directSubtypes = [];

  ProtocolMessageType(this.name);

  ProtocolMessageType? get parent => _parent;

  String get enumTypeName =>
      '${name.substring(0, 1).toLowerCase()}${name.substring(1)}';

  set parent(ProtocolMessageType parent) {
    _parent = parent;
    parent.isAbstract = true;
    parent.directSubtypes.add(this);
  }

  void field(
    String name,
    String protocol,
    FieldType type, {
    bool nullable = false,
  }) {
    fields.add(ProtocolMessageField(name, protocol, type, nullable));
  }

  static final message = ProtocolMessageType('Message');

  static final request = ProtocolMessageType('Request')
    ..parent = message
    ..field('requestId', _UniqueFieldNames.id, .integer)
    ..field(
      'databaseId',
      _UniqueFieldNames.databaseId,
      .integer,
      nullable: true,
    );

  static final openRequest = ProtocolMessageType('OpenRequest')
    ..parent = request
    ..field('databaseName', _UniqueFieldNames.databaseName, .string)
    ..field(
      'storageMode',
      _UniqueFieldNames.storageMode,
      .fileSystemImplementation,
    )
    ..field('wasmUri', _UniqueFieldNames.wasmUri, .uri)
    ..field('onlyOpenVfs', _UniqueFieldNames.onlyOpenVfs, .boolean)
    ..field('additionalData', _UniqueFieldNames.additionalData, .any);
}

final class ProtocolMessageField {
  final String name;
  final String protocolName;
  final FieldType type;
  final bool nullable;

  ProtocolMessageField(this.name, this.protocolName, this.type, this.nullable);
}

final class FieldConstructorInfo {
  final String type;
  final String dartName;
  final String? fixedValue;
  final FieldType? fieldType;

  FieldConstructorInfo(
    this.type,
    this.dartName,
    this.fixedValue, [
    this.fieldType,
  ]);
}

enum FieldType {
  any,
  boolean,
  integer,
  string,
  uri,
  fileSystemImplementation;

  bool get needsWrapper {
    return switch (this) {
      .uri || .fileSystemImplementation => true,
      _ => false,
    };
  }

  String get representationType {
    return switch (this) {
      .any => 'JSAny',
      .boolean => 'bool',
      .integer => 'int',
      .string || .uri || .fileSystemImplementation => 'String',
    };
  }

  String get dartType {
    return switch (this) {
      .any => 'JSAny',
      .boolean => 'bool',
      .integer => 'int',
      .string => 'String',
      .uri => 'Uri',
      .fileSystemImplementation => 'FileSystemImplementation',
    };
  }

  String dartToRepr(String dartExpr) {
    return switch (this) {
      FieldType.uri => '$dartExpr.toString()',
      FieldType.fileSystemImplementation => '$dartExpr.name',
      _ => dartExpr,
    };
  }
}

/// Field names used when serializing messages to JS objects.
///
/// Since we're using unsafe JS interop here, these can't be mangled by dart2js.
/// Thus, we should keep them short.
class _UniqueFieldNames {
  static const action = 'a'; // Only used in StreamRequest
  static const additionalData = 'a'; // only used in OpenRequest
  static const buffer = 'b';
  // no clash, used in RowResponse and RunQuery
  static const columnNames = 'c';
  static const checkInTransaction = 'c';
  static const databaseId = 'd';
  static const databaseName = 'd'; // no clash, used on different types
  static const errorMessage = 'e';
  static const fileType = 'f';
  static const id = 'i';
  static const updateKind = 'k';
  static const tableNames = 'n';
  static const onlyOpenVfs = 'o';
  static const parameters = 'p';
  static const storageMode = 's';
  static const serializedExceptionType = 's';
  static const sql = 's'; // not used in same message
  static const type = 't';
  static const wasmUri = 'u';
  static const updateTableName = 'u';
  static const responseData = 'r';
  static const returnRows = 'r';
  static const updateRowId = 'r';
  static const serializedException = 'r';
  static const rows = 'r'; // no clash, used on different message types
  static const typeVector = 'v';
  static const autocommit = 'x';
  static const lastInsertRowid = 'y';
  static const lockId = 'z';
}
