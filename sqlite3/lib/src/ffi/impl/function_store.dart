part of 'implementation.dart';

final FunctionStore functionStore = FunctionStore._();
late Bindings bindingsForStore;

/// Helper class to use abitrary functions as sqlite callbacks.
///
/// `dart:ffi`'s `Pointer.fromFunction` only supports static top-level functions
/// (in particular, no closures). All sqlite functions with callbacks allow us
/// to provide an application-specific `void*` pointer that will be forwarded to
/// the callback when invoked. We use an incrementing pointer for that, as it
/// allows us to identify functions.
class FunctionStore {
  final Map<int, dynamic> _functions = <int, dynamic>{};
  int _idCounter = 0;

  final Map<int, AggregateContext<dynamic>> _activeContexts = {};
  // Note: Needs to be >= 1 so that we can use 0 to check whether a new context
  // buffer has been created, see _xStepImpl for details.
  int _contextCounter = 1;

  FunctionStore._();

  void _forget(int id) {
    _functions.remove(id);
  }

  FunctionPointerAndData registerCollating(CollatingFunction f) {
    final id = _idCounter++;
    _functions[id] = f;

    return FunctionPointerAndData(
      xCompare: _xCompare,
      xDestroy: _xDestroy,
      applicationData: Pointer.fromAddress(id),
    );
  }

  FunctionPointerAndData registerScalar(ScalarFunction f) {
    final id = _idCounter++;
    _functions[id] = f;

    return FunctionPointerAndData(
      xFunc: _xFunc,
      xDestroy: _xDestroy,
      applicationData: Pointer.fromAddress(id),
    );
  }

  FunctionPointerAndData registerAggregate<V>(AggregateFunction<V> f) {
    assert(f is! WindowFunction<V>, 'Use registerWindow for window functions');

    final id = _idCounter++;
    _functions[id] = f;

    return FunctionPointerAndData(
      xStep: _xStep,
      xFinal: _xFinal,
      xDestroy: _xDestroy,
      applicationData: Pointer.fromAddress(id),
    );
  }

  FunctionPointerAndData registerWindow<V>(WindowFunction<V> f) {
    final id = _idCounter++;
    _functions[id] = f;

    return FunctionPointerAndData(
      xStep: _xStep,
      xFinal: _xFinal,
      xValue: _xValue,
      xInverse: _xInverse,
      xDestroy: _xDestroy,
      applicationData: Pointer.fromAddress(id),
    );
  }

  CollatingFunction readCollating(int id) {
    return _functions[id] as CollatingFunction;
  }

  ScalarFunction readScalar(int id) {
    return _functions[id] as ScalarFunction;
  }

  AggregateFunction<dynamic> readAggregate(int id) {
    return _functions[id] as AggregateFunction;
  }

  WindowFunction<dynamic> readWindow(int id) {
    return _functions[id] as WindowFunction;
  }
}

class FunctionPointerAndData {
  final Pointer<NativeType>? xCompare;
  final Pointer<NativeType>? xFunc;
  final Pointer<NativeType>? xStep;
  final Pointer<NativeType>? xFinal;
  final Pointer<NativeType>? xValue;
  final Pointer<NativeType>? xInverse;
  final Pointer<NativeType> xDestroy;

  final Pointer<NativeType> applicationData;

  FunctionPointerAndData({
    required this.xDestroy,
    required this.applicationData,
    this.xFunc,
    this.xStep,
    this.xFinal,
    this.xValue,
    this.xInverse,
    this.xCompare,
  });
}

int _collatingFunctionImpl(
  Pointer<Void> udp,
  int sizeA,
  Pointer<Void> textA,
  int sizeB,
  Pointer<Void> textB,
) {
  final functionId = udp.address;
  final target = functionStore.readCollating(functionId);

  final String txtA = textA.cast<sqlite3_char>().readString(sizeA);
  final String txtB = textB.cast<sqlite3_char>().readString(sizeB);

  try {
    return target(txtA, txtB);
  } on Object {
    return 0;
  }
}

void _scalarFunctionImpl(
  Pointer<sqlite3_context> context,
  int argCount,
  Pointer<Pointer<sqlite3_value>> args,
) {
  final functionId = context.getUserData(bindingsForStore).address;
  final target = functionStore.readScalar(functionId);

  final arguments = ValueList(argCount, args, bindingsForStore);

  try {
    context.setResult(bindingsForStore, target(arguments));
  } on Object catch (e) {
    context.setError(bindingsForStore, Error.safeToString(e));
  }
  arguments.isValid = false;
}

Pointer<Void> _xCompare = Pointer.fromFunction<
        Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Int32,
            Pointer<Void>)>(_collatingFunctionImpl, 0)
    .cast();

Pointer<Void> _xFunc = Pointer.fromFunction<
        Void Function(Pointer<sqlite3_context>, Int32,
            Pointer<Pointer<sqlite3_value>>)>(_scalarFunctionImpl)
    .cast();

void _xDestroyImpl(Pointer<Void> data) {
  functionStore._forget(data.address);
}

Pointer<Void> _xDestroy =
    Pointer.fromFunction<Void Function(Pointer<Void>)>(_xDestroyImpl).cast();

/// Reads or registers a Dart-managed [AggregateContext] for a given native
/// [context].
///
/// This will return null only if sqlite3 can't allocate the context, in which
/// case an error will be set on the [context] as well.
AggregateContext<dynamic>? _obtainOrCreateContext(
  Pointer<sqlite3_context> context,
  AggregateFunction<dynamic> function,
) {
  final agCtxPtr =
      context.aggregateContext(bindingsForStore, sizeOf<Int64>()).cast<Int64>();

  if (agCtxPtr.isNullPointer) {
    // We can't run without our 8 bytes! This indicates an out-of-memory error
    context.setError(bindingsForStore, 'internal error (OOM?)');
    return null;
  }

  // Ok, we have a pointer (that sqlite3 zeroes out for us). Our state counter
  // starts at one, so if it's still zero we don't have a Dart context yet.
  AggregateContext<dynamic> dartContext;
  if (agCtxPtr.value == 0) {
    dartContext = function.createContext();

    final ctxId = functionStore._contextCounter++;
    functionStore._activeContexts[ctxId] = dartContext;
    agCtxPtr.value = ctxId;
  } else {
    dartContext = functionStore._activeContexts[agCtxPtr.value]!;
  }
  return dartContext;
}

void _xStepImpl(
  Pointer<sqlite3_context> context,
  int argCount,
  Pointer<Pointer<sqlite3_value>> args,
) {
  final functionId = context.getUserData(bindingsForStore).address;
  final function = functionStore.readAggregate(functionId);

  final dartContext = _obtainOrCreateContext(context, function);
  if (dartContext == null) {
    // Internal error, handled by _obtainOrCreateContext
    return;
  }

  final arguments = ValueList(argCount, args, bindingsForStore);
  function.step(arguments, dartContext);
  arguments.isValid = false;
}

Pointer<Void> _xStep = Pointer.fromFunction<
        Void Function(Pointer<sqlite3_context>, Int32,
            Pointer<Pointer<sqlite3_value>>)>(_xStepImpl)
    .cast();

void _xValueImpl(Pointer<sqlite3_context> context) {
  final functionId = context.getUserData(bindingsForStore).address;
  final function = functionStore.readWindow(functionId);

  final dartContext = _obtainOrCreateContext(context, function);
  if (dartContext == null) {
    // Internal error, handled by _obtainOrCreateContext
    return;
  }

  context.setResultOf(() => function.value(dartContext));
}

Pointer<Void> _xValue =
    Pointer.fromFunction<Void Function(Pointer<sqlite3_context>)>(_xValueImpl)
        .cast();

void _xInverseImpl(Pointer<sqlite3_context> context, int nArgs,
    Pointer<Pointer<sqlite3_value>> args) {
  final functionId = context.getUserData(bindingsForStore).address;
  final function = functionStore.readWindow(functionId);

  final dartContext = _obtainOrCreateContext(context, function);
  if (dartContext == null) {
    // Internal error, handled by _obtainOrCreateContext
    return;
  }

  final arguments = ValueList(nArgs, args, bindingsForStore);
  function.inverse(arguments, dartContext);
  arguments.isValid = false;
}

Pointer<Void> _xInverse = Pointer.fromFunction<
        Void Function(Pointer<sqlite3_context>, Int32,
            Pointer<Pointer<sqlite3_value>>)>(_xInverseImpl)
    .cast();

void _xFinalImpl(Pointer<sqlite3_context> context) {
  final agCtxPtr = context.aggregateContext(bindingsForStore, 0).cast<Int64>();
  final functionId = context.getUserData(bindingsForStore).address;
  final function = functionStore.readAggregate(functionId);

  AggregateContext<dynamic> aggregateContext;

  // It will be != 0 if xStep was called before, since we require 0 bytes of
  // memory here and aggregate_context returns a null pointer for that. If
  // xStep allocated memory before, that pointer would be returned, and it would
  // point to an existing context.
  if (!agCtxPtr.isNullPointer) {
    aggregateContext = functionStore._activeContexts.remove(agCtxPtr.value)!;
  } else {
    aggregateContext = function.createContext();
  }

  context.setResultOf(() => function.finalize(aggregateContext));
}

Pointer<Void> _xFinal =
    Pointer.fromFunction<Void Function(Pointer<sqlite3_context>)>(_xFinalImpl)
        .cast();

extension on Pointer<sqlite3_context> {
  void setResultOf(Object? Function() function) {
    try {
      setResult(bindingsForStore, function());
    } on Object catch (e) {
      setError(bindingsForStore, Error.safeToString(e));
    }
  }
}
