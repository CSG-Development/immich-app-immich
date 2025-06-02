import 'dart:async';

import 'package:immich_mobile/domain/interfaces/secure_store.interface.dart';
import 'package:immich_mobile/domain/models/secure_store.model.dart';

class SecureStoreService {
  final ISecureStoreRepository _secureStoreRepository;

  final Map<int, dynamic> _cache = {};
  late final StreamSubscription<SecureStoreUpdateEvent> _secureStoreUpdateSubscription;

  SecureStoreService._({
    required ISecureStoreRepository storeRepository,
  }) : _secureStoreRepository = storeRepository;

  // TODO: Temporary typedef to make minimal changes. Remove this and make the presentation layer access store through a provider
  static SecureStoreService? _instance;
  static SecureStoreService get I {
    if (_instance == null) {
      throw UnsupportedError("SecureStoreService not initialized. Call init() first");
    }
    return _instance!;
  }

  // TODO: Replace the implementation with the one from create after removing the typedef
  /// Initializes the store with the given [storeRepository]
  static Future<SecureStoreService> init({
    required ISecureStoreRepository storeRepository,
  }) async {
    _instance ??= await create(storeRepository: storeRepository);
    return _instance!;
  }

  /// Initializes the store with the given [storeRepository]
  static Future<SecureStoreService> create({
    required ISecureStoreRepository storeRepository,
  }) async {
    final instance = SecureStoreService._(storeRepository: storeRepository);
    await instance._populateCache();
    instance._secureStoreUpdateSubscription = instance._listenForChange();
    return instance;
  }

  /// Fills the cache with the values from the DB
  Future<void> _populateCache() async {
    for (SecureStoreKey key in SecureStoreKey.values) {
      final storeValue = await _secureStoreRepository.tryGet(key);
      _cache[key.id] = storeValue;
    }
  }

  /// Listens for changes in the DB and updates the cache
  StreamSubscription<SecureStoreUpdateEvent> _listenForChange() =>
      _secureStoreRepository.watchAll().listen((event) {
        _cache[event.key.id] = event.value;
      });

  /// Disposes the store and cancels the subscription. To reuse the store call init() again
  void dispose() async {
    await _secureStoreUpdateSubscription.cancel();
    _cache.clear();
  }

  /// Returns the stored value for the given key (possibly null)
  T? tryGet<T>(SecureStoreKey<T> key) => _cache[key.id];

  /// Returns the stored value for the given key or if null the [defaultValue]
  /// Throws a [SecureStoreKeyNotFoundException] if both are null
  T get<T>(SecureStoreKey<T> key, [T? defaultValue]) {
    final value = tryGet(key) ?? defaultValue;
    if (value == null) {
      throw SecureStoreKeyNotFoundException(key);
    }
    return value;
  }

  /// Asynchronously stores the value in the Store
  Future<void> put<U extends SecureStoreKey<T>, T>(U key, T value) async {
    if (_cache[key.id] == value) return;
    await _secureStoreRepository.insert(key, value);
    _cache[key.id] = value;
  }

  /// Watches a specific key for changes
  Stream<T?> watch<T>(SecureStoreKey<T> key) => _secureStoreRepository.watch(key);

  /// Removes the value asynchronously from the Store
  Future<void> delete<T>(SecureStoreKey<T> key) async {
    await _secureStoreRepository.delete(key);
    _cache.remove(key.id);
  }

  /// Clears all values from this store (cache and DB)
  Future<void> clear() async {
    await _secureStoreRepository.deleteAll();
    _cache.clear();
  }
}

class SecureStoreKeyNotFoundException implements Exception {
  final SecureStoreKey key;
  const SecureStoreKeyNotFoundException(this.key);

  @override
  String toString() => "Key - <${key.name}> not available in Store";
}
