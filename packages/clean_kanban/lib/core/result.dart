/// A sealed class representing the result of an operation that can either succeed or fail.
///
/// The [Result] class is generic over type [T] which represents the type of the
/// successful value. Use [Success] for successful operations and [Failure] for
/// failed operations.
sealed class Result<T> {
  /// Creates a new [Result] instance.
  const Result();
}

/// Represents a successful result containing a value of type [T].
class Success<T> extends Result<T> {
  /// The successful value of type [T].
  final T value;

  /// Creates a new [Success] instance with the given [value].
  const Success(this.value);
}

/// Represents a failed result containing an error message.
class Failure<T> extends Result<T> {
  /// The error message describing why the operation failed.
  final String message;

  /// Creates a new [Failure] instance with the given error [message].
  const Failure(this.message);
}
