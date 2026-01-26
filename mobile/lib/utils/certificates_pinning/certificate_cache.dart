/// A single cache entry for certificate validation.
class _CertificateCacheEntry {
  final bool isValid;
  final DateTime validUntil;

  _CertificateCacheEntry(this.isValid, this.validUntil);
}

/// In-memory cache for certificate validation results.
class CertificateCache {
  final Duration _entryTTL;
  final Map<String, _CertificateCacheEntry> _cache = {};

  CertificateCache({required Duration entryTTL}) : _entryTTL = entryTTL;

  /// Returns cached validation result if still valid, otherwise `null`.
  bool? getCachedValidation(String cacheKey) {
    final entry = _cache[cacheKey];

    if (entry == null) {
      return null;
    }

    if (DateTime.now().isAfter(entry.validUntil)) {
      _cache.remove(cacheKey);
      return null;
    }

    return entry.isValid;
  }

  /// Stores validation result in cache.
  void cacheValidation(String cacheKey, bool isValid) {
    _cache[cacheKey] = _CertificateCacheEntry(
      isValid,
      DateTime.now().add(_entryTTL),
    );
  }

  /// Clears all cached entries.
  void clear() {
    _cache.clear();
  }

  /// Removes expired entries from cache.
  void cleanExpired() {
    final now = DateTime.now();
    _cache.removeWhere((key, entry) => now.isAfter(entry.validUntil));
  }

  /// Total number of entries in cache.
  int get size => _cache.length;

  /// Number of currently valid entries in cache.
  int get validCount {
    final now = DateTime.now();
    return _cache.values
        .where((entry) => entry.isValid && now.isBefore(entry.validUntil))
        .length;
  }
}

