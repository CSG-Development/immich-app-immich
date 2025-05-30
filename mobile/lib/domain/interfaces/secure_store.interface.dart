import 'package:immich_mobile/domain/models/secure_store.model.dart';

abstract interface class ISecureStoreRepository {
  Future<bool> insert<T>(SecureStoreKey<T> key, T value);

  Future<T?> tryGet<T>(SecureStoreKey<T> key);

  Stream<T?> watch<T>(SecureStoreKey<T> key);

  Stream<SecureStoreUpdateEvent> watchAll();

  Future<bool> update<T>(SecureStoreKey<T> key, T value);

  Future<void> delete<T>(SecureStoreKey<T> key);

  Future<void> deleteAll();
}
