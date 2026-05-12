class ProviderNotReadyError extends StateError {
  ProviderNotReadyError(String providerName, String dependency)
    : super('$providerName is not ready: missing $dependency');
}

enum RemoteCodeFailureType { invalidCode, expiredCode, unauthorized, unknown }

class RemoteCodeValidationError implements Exception {
  const RemoteCodeValidationError(this.type, this.message);

  final RemoteCodeFailureType type;
  final String message;
}
