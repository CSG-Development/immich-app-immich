import 'package:immich_mobile/domain/interfaces/secure_store.interface.dart';
import 'package:immich_mobile/domain/models/secure_store.model.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStoreRepository implements ISecureStoreRepository {
  final FlutterSecureStorage _storage;
  final Map<int, dynamic> _cache = {};

  SecureStoreRepository() : _storage = const FlutterSecureStorage();

  @override
  Future<bool> insert<T>(SecureStoreKey<T> key, T value) async {
    try {
      final stringValue = _serializeValue(value);
      await _storage.write(key: key.name, value: stringValue);
      _cache[key.id] = value;
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<T?> tryGet<T>(SecureStoreKey<T> key) async {
    try {
      final stringValue = await _storage.read(key: key.name);
      if (stringValue == null) return null;
      final value = _deserializeValue<T>(stringValue);
      _cache[key.id] = value;
      return value;
    } catch (e) {
      return null;
    }
  }

  @override
  Stream<T?> watch<T>(SecureStoreKey<T> key) async* {
    yield* Stream.periodic(const Duration(milliseconds: 100))
        .asyncMap((_) => tryGet(key));
  }

  @override
  Stream<SecureStoreUpdateEvent> watchAll() async* {
    yield* Stream.periodic(const Duration(milliseconds: 100))
        .asyncMap((_) async {
      final events = <SecureStoreUpdateEvent>[];
      for (final key in SecureStoreKey.values) {
        final value = await tryGet(key);
        events.add(SecureStoreUpdateEvent(key, value));
      }
      return events;
    }).asyncExpand((events) => Stream.fromIterable(events));
  }

  @override
  Future<bool> update<T>(SecureStoreKey<T> key, T value) async {
    return insert(key, value);
  }

  @override
  Future<void> delete<T>(SecureStoreKey<T> key) async {
    await _storage.delete(key: key.name);
    _cache.remove(key.id);
  }

  @override
  Future<void> deleteAll() async {
    await _storage.deleteAll();
    _cache.clear();
  }

  String _serializeValue<T>(T value) {
    if (value == null) return '';
    return value.toString();
  }

  T? _deserializeValue<T>(String value) {
    if (value.isEmpty) return null;
    return value as T;
  }
}
