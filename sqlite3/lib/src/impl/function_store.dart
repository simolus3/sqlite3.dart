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
    final id = _idCounter++;
    _functions[id] = f;

    return FunctionPointerAndData(
      xStep: _xStep,
      xFinal: _xFinal,
      xDestroy: _xDestroy,
      applicationData: Pointer.fromAddress(id),
    );
  }

  ScalarFunction readScalar(int id) {
    return _functions[id] as ScalarFunction;
  }

  AggregateFunction<dynamic> readAggregate(int id) {
    return _functions[id] as AggregateFunction;
  }
}

class FunctionPointerAndData {
  final Pointer<NativeType>? xFunc;
  final Pointer<NativeType>? xStep;
  final Pointer<NativeType>? xFinal;
  final Pointer<NativeType> xDestroy;

  final Pointer<NativeType> applicationData;

  FunctionPointerAndData({
    required this.xDestroy,
    required this.applicationData,
    this.xFunc,
    this.xStep,
    this.xFinal,
  });
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
  } catch (e) {
    context.setError(bindingsForStore, Error.safeToString(e));
  }
  arguments.isValid = false;
}

Pointer<Void> _xFunc = Pointer.fromFunction<
        Void Function(Pointer<sqlite3_context>, Int32,
            Pointer<Pointer<sqlite3_value>>)>(_scalarFunctionImpl)
    .cast();

void _xDestroyImpl(Pointer<Void> data) {
  functionStore._forget(data.address);
}

Pointer<Void> _xDestroy =
    Pointer.fromFunction<Void Function(Pointer<Void>)>(_xDestroyImpl).cast();

void _xStepImpl(
  Pointer<sqlite3_context> context,
  int argCount,
  Pointer<Pointer<sqlite3_value>> args,
) {
  final agCtxPtr =
      context.aggregateContext(bindingsForStore, sizeOf<Int64>()).cast<Int64>();

  if (agCtxPtr.isNullPointer) {
    // We can't run without our 8 bytes! This indicates an out-of-memory error
    context.setError(bindingsForStore, 'internal error (OOM?)');
    return;
  }

  final functionId = context.getUserData(bindingsForStore).address;
  final function = functionStore.readAggregate(functionId);

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

  final arguments = ValueList(argCount, args, bindingsForStore);
  function.step(arguments, dartContext);
  arguments.isValid = false;
}

Pointer<Void> _xStep = Pointer.fromFunction<
        Void Function(Pointer<sqlite3_context>, Int32,
            Pointer<Pointer<sqlite3_value>>)>(_xStepImpl)
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
    aggregateContext = functionStore._activeContexts[agCtxPtr.value]!;
    functionStore._activeContexts.remove(agCtxPtr.value);
  } else {
    aggregateContext = function.createContext();
  }

  try {
    context.setResult(bindingsForStore, function.finalize(aggregateContext));
  } catch (e) {
    context.setError(bindingsForStore, Error.safeToString(e));
  }
}

Pointer<Void> _xFinal =
    Pointer.fromFunction<Void Function(Pointer<sqlite3_context>)>(_xFinalImpl)
        .cast();
