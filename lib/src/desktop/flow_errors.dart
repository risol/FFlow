class FlowWorkerException implements Exception {
  const FlowWorkerException(this.code, this.message,
      {this.diagnostics = const {}});
  final String code;
  final String message;

  /// Available task measurements when the failure occurred in a worker.
  final Map<String, Object?> diagnostics;
  @override
  String toString() => '$code: $message';
}
