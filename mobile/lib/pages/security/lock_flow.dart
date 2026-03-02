enum LockFlow {
  /// Validate an existing lock without changing it.
  validate,

  /// Create or update a lock.
  create,

  /// Remove an existing lock.
  remove,
}

