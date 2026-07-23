import 'failure.dart';

/// A minimal Either-style result type: either a [Failure] or a success
/// value of type [T]. Every repository and use case in the app returns
/// `Future<Result<T>>` instead of throwing — this makes error handling
/// explicit and forces the presentation layer to handle both branches.
sealed class Result<T> {
  const Result();

  const factory Result.success(T value) = Success<T>;
  const factory Result.failure(Failure failure) = Failure_<T>;

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure_<T>;

  /// Returns the success value or null.
  T? get valueOrNull => switch (this) {
        Success<T>(value: final v) => v,
        Failure_<T>() => null,
      };

  /// Returns the failure or null.
  Failure? get failureOrNull => switch (this) {
        Success<T>() => null,
        Failure_<T>(failure: final f) => f,
      };

  /// Pattern-match helper for concise handling in the UI layer.
  R when<R>({
    required R Function(T value) success,
    required R Function(Failure failure) failure,
  }) {
    return switch (this) {
      Success<T>(value: final v) => success(v),
      Failure_<T>(failure: final f) => failure(f),
    };
  }
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure_<T> extends Result<T> {
  const Failure_(this.failure);
  final Failure failure;
}
