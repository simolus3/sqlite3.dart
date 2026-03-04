import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:collection/collection.dart';
import 'package:dart_style/dart_style.dart';
import 'package:pub_semver/pub_semver.dart';

// This tool generates `lib/src/protocol/helper.g.dart` containing an
// enumeration of message types and utilities to generate messages as object
// literals.
void main() {
  final types = ProtocolMessageType.readFromDart(
    File('lib/src/protocol/messages.dart').readAsStringSync(),
  );

  final codegen = DartCodeGenerator()..generate(types);
  File('lib/src/protocol/helper.g.dart').writeAsStringSync(codegen.content);
}

final class ProtocolMessageType {
  final String name;

  /// The name of this message type in `MessageType` enum.
  final String messageTypeName;
  final bool isAbstract;
  final List<ProtocolMessageField> definedFields = [];
  final ProtocolMessageType? parent;

  ProtocolMessageType({
    required this.name,
    required this.messageTypeName,
    this.parent,
    this.isAbstract = false,
  });

  String get requestMethodName {
    final firstChar = messageTypeName.substring(0, 1);
    final rest = messageTypeName.substring(1);

    return 'handle${firstChar.toUpperCase()}$rest';
  }

  Iterable<ProtocolMessageField> get allFields sync* {
    final fieldNames = <String>{};

    ProtocolMessageType? current = this;
    while (current != null) {
      for (final field in current.definedFields) {
        if (fieldNames.add(field.javaScriptName)) {
          yield field;
        }
      }

      current = current.parent;
    }
  }

  bool inheritsFromName(String name) {
    return switch (parent) {
      null => false,
      final parent => parent.name == name || parent.inheritsFromName(name),
    };
  }

  static List<ProtocolMessageType> readFromDart(String source) {
    final parsed = parseString(
      content: source,
      featureSet: FeatureSet.latestLanguageVersion(),
    ).unit;

    final messageTypes = <String, ProtocolMessageType>{};
    final uniqueFieldNames = UniqueFieldNames();
    // First, read unique field names (used to resolve @JS annotations without
    // having to fully resolve the source file).
    for (final declaration in parsed.declarations) {
      if (declaration is ClassDeclaration &&
          declaration.namePart.typeName.lexeme == '_UniqueFieldNames') {
        uniqueFieldNames.readFrom(declaration);
      }
    }

    for (final declaration in parsed.declarations) {
      if (declaration is ExtensionTypeDeclaration) {
        final implements = declaration.implementsClause;
        if (implements == null || implements.interfaces.length != 1) {
          continue;
        }

        final name = declaration.primaryConstructor.typeName.lexeme;
        var isAbstract = false;
        var messageTypeName = name;
        for (final annotation in declaration.metadata) {
          if (_isAnnotation(annotation, 'abstract')) {
            isAbstract = true;
          }
          if (annotation.name.name == 'MessageTypeName') {
            messageTypeName =
                (annotation.arguments!.arguments[0] as SimpleStringLiteral)
                    .value;
          }
        }

        ProtocolMessageType? resolvedParentType;
        if (name != 'Message') {
          final parentTypeName = implements.interfaces[0].name.lexeme;
          resolvedParentType = messageTypes[parentTypeName];
          if (resolvedParentType == null) {
            throw 'For $name: Could not find $parentTypeName';
          }
        }

        final definedType = ProtocolMessageType(
          name: name,
          messageTypeName: messageTypeName,
          parent: resolvedParentType,
          isAbstract: isAbstract,
        );
        messageTypes[name] = definedType;

        for (final definition in declaration.body.childEntities) {
          if (definition is FieldDeclaration) {
            String? jsName;
            TransferMode mode = TransferMode.clone;
            for (final annotation in definition.metadata) {
              if (uniqueFieldNames.readJsAnnotation(annotation)
                  case final name?) {
                jsName = name;
                continue;
              }

              if (_isAnnotation(annotation, 'transfer')) {
                mode = TransferMode.move;
              } else if (_isAnnotation(annotation, 'transferIfArrayBuffer')) {
                mode = TransferMode.moveIfArrayBuffer;
              }
            }

            final type = definition.fields.type!;
            for (final field in definition.fields.variables) {
              definedType.definedFields.add(
                ProtocolMessageField(
                  dartType: source.substring(type.offset, type.end),
                  dartName: field.name.lexeme,
                  javaScriptName: jsName ?? field.name.lexeme,
                  isMessageType: _hasAnnotation(definition, 'isType'),
                  transferMode: mode,
                ),
              );
            }
          }
        }
      }
    }

    return messageTypes.values.toList();
  }

  static bool _isAnnotation(Annotation annotation, String name) {
    return annotation.name.name == name;
  }

  static bool _hasAnnotation(AnnotatedNode node, String name) {
    return node.metadata.any((a) => _isAnnotation(a, name));
  }
}

final class ProtocolMessageField {
  final String dartName;
  final String dartType;
  final String javaScriptName;

  /// Whether this is the `type` field on `Message`.
  ///
  /// This field is auto-generated for each subtype.
  final bool isMessageType;

  final TransferMode transferMode;

  ProtocolMessageField({
    required this.dartName,
    required this.dartType,
    required this.javaScriptName,
    this.isMessageType = false,
    this.transferMode = TransferMode.clone,
  });
}

enum TransferMode { clone, move, moveIfArrayBuffer }

/// Parsed `_UniqueFIeldNames` constants, used to resolve `@JS` annotations.
final class UniqueFieldNames {
  final Map<String, String> fieldValues = {};

  void readFrom(ClassDeclaration declaration) {
    for (final child in declaration.body.childEntities) {
      if (child is FieldDeclaration) {
        for (final variable in child.fields.variables) {
          final value = variable.initializer as SimpleStringLiteral;
          fieldValues[variable.name.lexeme] = value.value;
        }
      }
    }
  }

  String? readJsAnnotation(Annotation annotation) {
    if (annotation.name.name == 'JS') {
      final arg = annotation.arguments!.arguments[0];
      if (arg is SimpleStringLiteral) {
        return arg.value;
      }
      if (arg is PrefixedIdentifier && arg.prefix.name == '_UniqueFieldNames') {
        return fieldValues[arg.identifier.name]!;
      }

      throw 'Unsupported @JS argument';
    }

    return null;
  }
}

final class DartCodeGenerator {
  final buffer = StringBuffer("""
// Generated by tool/protocol_generator.dart, do not modify by hand.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' show AbortSignal;
import 'package:sqlite3/wasm.dart' show WorkerOptions;

import '../channel.dart';
import 'messages.dart';

""");

  String get content {
    final formatter = DartFormatter(languageVersion: Version(3, 10, 0));
    try {
      return formatter.format(buffer.toString());
    } on Object {
      // Probably a syntax error in sources, we want to inspect that further.
      return buffer.toString();
    }
  }

  void generate(List<ProtocolMessageType> types) {
    _generateMessageTypeEnum(types);
    _generateRequestHandler(types);
    _generateFactories(types);
    _generateExtractTransferrable(types);
    _generateDispatchMessage(types);
  }

  void _generateMessageTypeEnum(List<ProtocolMessageType> types) {
    buffer.writeln('enum MessageType<T extends Message> {');
    for (final type in types) {
      if (type.isAbstract) continue;

      buffer.writeln('  ${type.messageTypeName}<${type.name}>(),');
    }
    buffer.writeln('}');
  }

  void _generateRequestHandler(List<ProtocolMessageType> types) {
    buffer.writeln('abstract base class RequestHandler {');
    for (final type in types) {
      if (type.isAbstract || !type.inheritsFromName('Request')) continue;

      buffer
        ..writeln(
          'FutureOr<Response> ${type.requestMethodName}'
          '(${type.name} request, AbortSignal abortSignal) => '
          '_unsupportedRequest(request);',
        )
        ..writeln();
    }

    buffer.writeln('Future<Never> _unsupportedRequest(Request request) {');
    buffer.writeln(
      "  return Future.error(ArgumentError('Unsupported request \${request.type}'));",
    );
    buffer.writeln('}');

    buffer.writeln(
      'FutureOr<Response> dispatchRequest(Request request, AbortSignal abortSignal) {',
    );
    buffer.writeln('switch(request.type) {');
    for (final type in types) {
      if (type.isAbstract || !type.inheritsFromName('Request')) continue;

      buffer.write("case '${type.messageTypeName}': return ");
      buffer.writeln(
        '${type.requestMethodName}(request as ${type.name}, abortSignal);',
      );
    }
    buffer.writeln('default: return _unsupportedRequest(request);');
    buffer.writeln('}');
    buffer.writeln('}');

    buffer.writeln('}');
  }

  void _generateFactories(List<ProtocolMessageType> types) {
    for (final type in types) {
      if (type.isAbstract) continue;
      final name = type.name;

      buffer
        ..writeln('@anonymous')
        ..writeln('extension type _$name._($name _) implements $name {')
        ..writeln('external factory _$name({');

      for (final field in type.allFields) {
        buffer
          ..write(" @JS('${field.javaScriptName}')")
          ..write('required ${field.dartType} ${field.dartName},');
      }

      buffer
        ..writeln('});')
        ..writeln('}')
        ..write(type.name)
        ..write(' new${type.name}({');

      final defaultValues = <String, String>{};
      for (final field in type.allFields) {
        var hasDefault = false;

        if (field.isMessageType) {
          defaultValues[field.dartName] = "'${type.messageTypeName}'";
          hasDefault = true;
          continue;
        }

        if (!hasDefault) {
          buffer.write('required ');
        }

        buffer
          ..write('${field.dartType}  ')
          ..write(field.dartName)
          ..writeln(', ');
      }

      buffer
        ..writeln('}) {')
        ..write('  return _$name(');

      for (final field in type.allFields) {
        buffer
          ..write(field.dartName)
          ..write(': ');

        if (defaultValues[field.dartName] case final defaultValue?) {
          buffer.write(defaultValue);
        } else {
          buffer.write(field.dartName);
        }

        buffer.writeln(', ');
      }

      buffer
        ..writeln(');')
        ..writeln('}');
    }
  }

  void _generateExtractTransferrable(List<ProtocolMessageType> types) {
    buffer
      ..writeln(r"@JS('ArrayBuffer')")
      ..writeln('external JSFunction get _arrayBufferConstructor;')
      ..writeln('JSArray<JSAny> extractTransferrable(Message message) {')
      ..writeln('final result = JSArray<JSAny>();')
      ..writeln('switch (message.type) {');

    for (final type in types) {
      if (type.isAbstract) continue;

      final statements = <String>[];
      String addToResult(String expr) {
        return 'result.add($expr);';
      }

      for (final field in type.allFields) {
        final expr = '(message as ${type.name}).${field.dartName}';

        switch (field.transferMode) {
          case TransferMode.clone:
            // Don't include this field in transferrable
            continue;
          case TransferMode.move:
            final isNullable = field.dartType.endsWith('?');
            if (field.dartType == 'WebEndpoint') {
              statements.add(addToResult('$expr.port'));
            } else if (isNullable) {
              statements.add('if ($expr case final e?) ${addToResult('e')}');
            } else {
              statements.add(addToResult(expr));
            }
          case TransferMode.moveIfArrayBuffer:
            statements.add(
              'if ($expr case JSAny a when a.instanceof(_arrayBufferConstructor)) {${addToResult('a')}}',
            );
        }
      }

      if (statements.isNotEmpty) {
        buffer.writeln(
          "case '${type.messageTypeName}': ${statements.join()}break;",
        );
      }
    }

    buffer
      ..writeln('}')
      ..writeln('return result;')
      ..writeln('}');
  }

  void _generateDispatchMessage(List<ProtocolMessageType> types) {
    final typesDirectlyExtendingMessage = types
        .where(
          (t) => switch (t.parent) {
            ProtocolMessageType(name: 'Message') => true,
            _ => false,
          },
        )
        .toList();

    Iterable<ProtocolMessageType> subtypesOf(ProtocolMessageType type) {
      return types.where((sub) => sub.inheritsFromName(type.name));
    }

    typesDirectlyExtendingMessage.sortBy((parent) => subtypesOf(parent).length);

    buffer.writeln('T dispatchMessage<T>(Message msg, {');
    for (final type in typesDirectlyExtendingMessage) {
      buffer.writeln('  required T Function(${type.name}) when${type.name},');
    }
    buffer
      ..writeln('})  {')
      ..writeln('switch (msg.type) {');

    for (final type in typesDirectlyExtendingMessage) {
      if (type != typesDirectlyExtendingMessage.last) {
        var subTypes = subtypesOf(type);
        if (!type.isAbstract) {
          subTypes = subTypes.followedBy([type]);
        }

        for (final subType in subTypes) {
          buffer.writeln("case '${subType.messageTypeName}':");
        }
      } else {
        // We've covered all other cases, so handle this one as a default.
        buffer.write('default:');
      }

      buffer.writeln('return when${type.name}(msg as ${type.name});');
    }

    buffer
      ..writeln('}')
      ..writeln('}');
  }
}
