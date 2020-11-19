import 'package:meta/meta.dart';

/// A scalar function exposed to sql.
///
/// {@template sqlite3_function_behavior}
/// The function must either return a `bool`, `num`, `String`, `List<int>` or
/// `null`.
///
/// If invoking the function throws a Dart exception, the sql function will
/// result with an error result as well.
/// {@endtemplate}
typedef ScalarFunction = Object? Function(List<Object?> arguments);

/// Interface for application-defined aggregate functions.
///
/// A subclass of [AggregateFunction] should hold no state across invocations.
/// All its state needed during a computation should be stored in an instance of
/// [V].
///
/// As an example, take a look at the following Dart implementation of the
/// `count()` aggregate. Recall that there are two versions of `count()`. With
/// zero arguments, `count()` returns the number of rows. With one argument,
/// `count()` returns the number of times that the argument was non-null.
///
/// ```dart
/// class MyCount implements AggregateFunction<int> {
///  @override
///  AggregateContext<int> createContext() => AggregateContext(0);
///
///  @override
///  void step(List<Object> arguments, AggregateContext<int> context) {
///    if (arguments.isEmpty || arguments.first != null) {
///      context.value++;
///    }
///  }
///
///  @override
///  Object finalize(AggregateContext<int> context) {
///    return context.value;
///  }
///}
/// ```
@immutable
abstract class AggregateFunction<V> {
  /// Creates an initial context holding the initial value before [step] is
  /// called.
  ///
  /// If [step] is never called before the query concludes, the initial context
  /// is also used for [finalize].
  AggregateContext<V> createContext();

  /// Adds a new row to the aggregate.
  ///
  /// The [context] should be modified to reflect the new row calling this
  /// function with [arguments].
  void step(List<Object?> arguments, AggregateContext<V> context);

  /// Computes the final value from a populated [context].
  ///
  /// {@macro sqlite3_function_behavior}
  Object? finalize(AggregateContext<V> context);
}

/// Application-defined context used to compute results in aggregate functions.
class AggregateContext<V> {
  /// The current value of this context.
  V value;

  /// Creates a context with an initial [value].
  AggregateContext(this.value);
}

/// Describes how many arguments an application-defined sql function can take.
class AllowedArgumentCount {
  final int allowedArgs;

  const AllowedArgumentCount(this.allowedArgs);
  const AllowedArgumentCount.any() : allowedArgs = -1;
}
