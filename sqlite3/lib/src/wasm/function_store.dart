import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../common/constants.dart';
import '../common/functions.dart';

import 'bindings.dart';

class FunctionStore {
  final Map<int, dynamic> _functions = <int, dynamic>{};
  final Map<int, AggregateContext<Object?>> _contexts = {};

  final WasmBindings _bindings;

  int _idCounter = 0;
  // Note: Needs to be >= 1 so that we can use 0 to check whether a new context
  // buffer has been created, see runStepFunction for details.
  int _contextCounter = 1;

  FunctionStore(this._bindings);

  int register(dynamic f) {
    final id = _idCounter++;
    _functions[id] = f;

    return id;
  }

  void forget(int id) => _functions.remove(id);

  void runScalarFunction(Pointer context, int argCount, Pointer args) {
    final functionId = _userDataForContext(context);
    final target = _functions[functionId] as ScalarFunction;
    final values = ValueList(argCount, args, this);

    try {
      _contextSetResult(context, target(values));
    } on Object catch (e) {
      _contextSetError(context, Error.safeToString(e));
    } finally {
      values.isValid = false;
    }
  }

  /// Attempts to obtain a Dart function context from the raw sql [context].
  ///
  /// Will return null and set an error on the context if the 4 byte necessary
  /// to identify the context number can't be allocated.
  AggregateContext<Object?>? _obtainOrCreateContext(
      Pointer context, AggregateFunction<Object?> function) {
    final agCtxPointer = _bindings.sqlite3_aggregate_context(context, 4);

    if (agCtxPointer == 0) {
      // Couldn't allocate memory for aggregate context => fail
      _contextSetError(context, 'internal error (OOM?)');
      return null;
    }

    // We have an aggregate context pointer, which is going to point to a value
    // of zero if no context has been created yet.
    AggregateContext<Object?> dartContext;
    final value = _bindings.int32ValueOfPointer(agCtxPointer);
    if (value == 0) {
      dartContext = function.createContext();

      final ctxId = _contextCounter++;
      _contexts[ctxId] = dartContext;
      _bindings.setInt32Value(agCtxPointer, ctxId);
    } else {
      dartContext = _contexts[value]!;
    }

    return dartContext;
  }

  void runStepFunction(Pointer context, int argCount, Pointer args) {
    final function =
        _functions[_userDataForContext(context)] as AggregateFunction;

    final dartContext = _obtainOrCreateContext(context, function);
    if (dartContext == null) {
      // Error response is nset in _obtainOrCreateContext
      return;
    }

    final arguments = ValueList(argCount, args, this);
    function.step(arguments, dartContext);
    arguments.isValid = false;
  }

  void runInverseFunction(Pointer context, int argCount, Pointer args) {
    final function = _functions[_userDataForContext(context)] as WindowFunction;

    final dartContext = _obtainOrCreateContext(context, function);
    if (dartContext == null) {
      // Error response is nset in _obtainOrCreateContext
      return;
    }

    final arguments = ValueList(argCount, args, this);
    function.inverse(arguments, dartContext);
    arguments.isValid = false;
  }

  void _setResultOrError(Pointer context, Object? Function() body) {
    try {
      _contextSetResult(context, body());
    } on Object catch (e) {
      _contextSetError(context, Error.safeToString(e));
    }
  }

  void runValueFunction(Pointer context) {
    final function = _functions[_userDataForContext(context)] as WindowFunction;

    final dartContext = _obtainOrCreateContext(context, function);
    if (dartContext == null) {
      // Error response is nset in _obtainOrCreateContext
      return;
    }

    _setResultOrError(context, () => function.value(dartContext));
  }

  void runFinalFunction(Pointer context) {
    final agCtxPointer = _bindings.sqlite3_aggregate_context(context, 0);
    final function =
        _functions[_userDataForContext(context)] as AggregateFunction;

    AggregateContext<Object?> aggregateContext;

    // It will be != 0 if xStep was called before, since we require 0 bytes of
    // memory here and aggregate_context returns a null pointer for that. If
    // xStep allocated memory before, that pointer would be returned, and it would
    // point to an existing context.
    if (agCtxPointer != 0) {
      aggregateContext =
          _contexts.remove(_bindings.int32ValueOfPointer(agCtxPointer))!;
    } else {
      aggregateContext = function.createContext();
    }

    _setResultOrError(context, () => function.finalize(aggregateContext));
  }

  int _userDataForContext(Pointer context) {
    return _bindings.sqlite3_user_data(context);
  }

  void _contextSetResult(Pointer context, Object? result) {
    if (result == null) {
      _bindings.sqlite3_result_null(context);
    } else if (result is int) {
      _bindings.sqlite3_result_int64(context, BigInt.from(result));
    } else if (result is BigInt) {
      _bindings.sqlite3_result_int64(context, result);
    } else if (result is double) {
      _bindings.sqlite3_result_double(context, result);
    } else if (result is bool) {
      _bindings.sqlite3_result_int64(
          context, result ? BigInt.one : BigInt.zero);
    } else if (result is String) {
      final bytes = utf8.encode(result);
      final ptr = _bindings.allocateBytes(bytes);

      _bindings
        ..sqlite3_result_text(
            context, ptr, bytes.length, SqlSpecialDestructor.SQLITE_TRANSIENT)
        ..free(ptr);
    } else if (result is List<int>) {
      final ptr = _bindings.allocateBytes(result);

      _bindings
        ..sqlite3_result_blob64(
            context, ptr, result.length, SqlSpecialDestructor.SQLITE_TRANSIENT)
        ..free(ptr);
    }
  }

  void _contextSetError(Pointer context, String error) {
    final bytes = utf8.encode(error);
    final ptr = _bindings.allocateBytes(bytes);

    _bindings
      ..sqlite3_result_error(context, ptr, bytes.length)
      ..free(ptr);
  }

  Object? _valueRead(Pointer value) {
    final type = _bindings.sqlite3_value_type(value);
    switch (type) {
      case SqlType.SQLITE_INTEGER:
        return _bindings.sqlite3_value_int64(value);
      case SqlType.SQLITE_FLOAT:
        return _bindings.sqlite3_value_double(value);
      case SqlType.SQLITE_TEXT:
        final length = _bindings.sqlite3_value_bytes(value);
        return _bindings.memory
            .readString(_bindings.sqlite3_value_text(value), length);
      case SqlType.SQLITE_BLOB:
        final length = _bindings.sqlite3_value_bytes(value);
        if (length == 0) {
          // sqlite3_column_blob returns a null pointer for non-null blobs with
          // a length of 0. Note that we can distinguish this from a proper null
          // by checking the type (which isn't SQLITE_NULL)
          return Uint8List(0);
        }

        return _bindings.memory
            .copyRange(_bindings.sqlite3_value_blob(value), length);
      case SqlType.SQLITE_NULL:
      default:
        return null;
    }
  }
}

/// An unmodifiable Dart list backed by native sqlite3 values.
class ValueList extends ListBase<Object?> {
  @override
  final int length;
  final Pointer argArray;
  final FunctionStore store;

  bool isValid = true;

  final List<Object?> _cachedCopies;

  ValueList(this.length, this.argArray, this.store)
      : _cachedCopies = List.filled(length, null);

  @override
  set length(int length) {
    throw UnsupportedError('Changing the length of sql arguments in Dart');
  }

  @override
  Object? operator [](int index) {
    assert(
      isValid,
      'Invalid arguments. This commonly happens when an application-defined '
      'sql function leaks its arguments after it finishes running. '
      'Please use List.of(arguments) in the function to create a copy of '
      'the argument instead.',
    );
    RangeError.checkValidIndex(index, this, 'index', length);

    final cached = _cachedCopies[index];
    if (cached != null) {
      return cached;
    }

    final valuePtr = store._bindings
        .int32ValueOfPointer(argArray + index * WasmBindings.pointerSize);
    final result = store._valueRead(valuePtr);
    if (result is String || result is List<int>) {
      // Cache to avoid excessive copying in case the argument is loaded
      // multiple times
      _cachedCopies[index] = result;
    }

    return result;
  }

  @override
  void operator []=(int index, Object? value) {
    throw UnsupportedError('The argument list is mutable');
  }
}
