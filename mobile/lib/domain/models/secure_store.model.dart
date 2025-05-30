/// Key for each possible value in the `Store`.
/// Defines the data type for each value
enum SecureStoreKey<T> {
  accessToken<String>._(0);

  const SecureStoreKey._(this.id);
  final int id;
  Type get type => T;
}

class SecureStoreUpdateEvent<T> {
  final SecureStoreKey<T> key;
  final T? value;

  const SecureStoreUpdateEvent(this.key, this.value);

  @override
  String toString() {
    return '''
SecureStoreUpdateEvent: {
  key: $key,
  value: ${value ?? '<NA>'},
}''';
  }

  @override
  bool operator ==(covariant SecureStoreUpdateEvent<T> other) {
    if (identical(this, other)) return true;

    return other.key == key && other.value == value;
  }

  @override
  int get hashCode => key.hashCode ^ value.hashCode;
}
