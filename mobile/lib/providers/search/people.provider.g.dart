// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'people.provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$getAllPeopleHash() => r'2c5e6a207683f15ab209650615fdf9cb7f76c736';

/// See also [getAllPeople].
@ProviderFor(getAllPeople)
final getAllPeopleProvider =
    AutoDisposeFutureProvider<List<PersonDto>>.internal(
      getAllPeople,
      name: r'getAllPeopleProvider',
      debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
          ? null
          : _$getAllPeopleHash,
      dependencies: null,
      allTransitiveDependencies: null,
    );

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef GetAllPeopleRef = AutoDisposeFutureProviderRef<List<PersonDto>>;
String _$getAllPeopleWithParamsHash() =>
    r'bf58c2ab2c42b1bb6de0d741b46f2818d4f99f18';

/// Copied from Dart SDK
class _SystemHash {
  _SystemHash._();

  static int combine(int hash, int value) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + value);
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    return hash ^ (hash >> 6);
  }

  static int finish(int hash) {
    // ignore: parameter_assignments
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    // ignore: parameter_assignments
    hash = hash ^ (hash >> 11);
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// See also [getAllPeopleWithParams].
@ProviderFor(getAllPeopleWithParams)
const getAllPeopleWithParamsProvider = GetAllPeopleWithParamsFamily();

/// See also [getAllPeopleWithParams].
class GetAllPeopleWithParamsFamily extends Family<AsyncValue<List<PersonDto>>> {
  /// See also [getAllPeopleWithParams].
  const GetAllPeopleWithParamsFamily();

  /// See also [getAllPeopleWithParams].
  GetAllPeopleWithParamsProvider call(String? closestPersonId) {
    return GetAllPeopleWithParamsProvider(closestPersonId);
  }

  @override
  GetAllPeopleWithParamsProvider getProviderOverride(
    covariant GetAllPeopleWithParamsProvider provider,
  ) {
    return call(provider.closestPersonId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'getAllPeopleWithParamsProvider';
}

/// See also [getAllPeopleWithParams].
class GetAllPeopleWithParamsProvider
    extends AutoDisposeFutureProvider<List<PersonDto>> {
  /// See also [getAllPeopleWithParams].
  GetAllPeopleWithParamsProvider(String? closestPersonId)
    : this._internal(
        (ref) => getAllPeopleWithParams(
          ref as GetAllPeopleWithParamsRef,
          closestPersonId,
        ),
        from: getAllPeopleWithParamsProvider,
        name: r'getAllPeopleWithParamsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$getAllPeopleWithParamsHash,
        dependencies: GetAllPeopleWithParamsFamily._dependencies,
        allTransitiveDependencies:
            GetAllPeopleWithParamsFamily._allTransitiveDependencies,
        closestPersonId: closestPersonId,
      );

  GetAllPeopleWithParamsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.closestPersonId,
  }) : super.internal();

  final String? closestPersonId;

  @override
  Override overrideWith(
    FutureOr<List<PersonDto>> Function(GetAllPeopleWithParamsRef provider)
    create,
  ) {
    return ProviderOverride(
      origin: this,
      override: GetAllPeopleWithParamsProvider._internal(
        (ref) => create(ref as GetAllPeopleWithParamsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        closestPersonId: closestPersonId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<List<PersonDto>> createElement() {
    return _GetAllPeopleWithParamsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is GetAllPeopleWithParamsProvider &&
        other.closestPersonId == closestPersonId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, closestPersonId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin GetAllPeopleWithParamsRef
    on AutoDisposeFutureProviderRef<List<PersonDto>> {
  /// The parameter `closestPersonId` of this provider.
  String? get closestPersonId;
}

class _GetAllPeopleWithParamsProviderElement
    extends AutoDisposeFutureProviderElement<List<PersonDto>>
    with GetAllPeopleWithParamsRef {
  _GetAllPeopleWithParamsProviderElement(super.provider);

  @override
  String? get closestPersonId =>
      (origin as GetAllPeopleWithParamsProvider).closestPersonId;
}

String _$personAssetsHash() => r'c1d35ee0e024bd6915e21bc724be4b458a14bc24';

/// See also [personAssets].
@ProviderFor(personAssets)
const personAssetsProvider = PersonAssetsFamily();

/// See also [personAssets].
class PersonAssetsFamily extends Family<AsyncValue<RenderList>> {
  /// See also [personAssets].
  const PersonAssetsFamily();

  /// See also [personAssets].
  PersonAssetsProvider call(String personId) {
    return PersonAssetsProvider(personId);
  }

  @override
  PersonAssetsProvider getProviderOverride(
    covariant PersonAssetsProvider provider,
  ) {
    return call(provider.personId);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'personAssetsProvider';
}

/// See also [personAssets].
class PersonAssetsProvider extends AutoDisposeFutureProvider<RenderList> {
  /// See also [personAssets].
  PersonAssetsProvider(String personId)
    : this._internal(
        (ref) => personAssets(ref as PersonAssetsRef, personId),
        from: personAssetsProvider,
        name: r'personAssetsProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$personAssetsHash,
        dependencies: PersonAssetsFamily._dependencies,
        allTransitiveDependencies:
            PersonAssetsFamily._allTransitiveDependencies,
        personId: personId,
      );

  PersonAssetsProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.personId,
  }) : super.internal();

  final String personId;

  @override
  Override overrideWith(
    FutureOr<RenderList> Function(PersonAssetsRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: PersonAssetsProvider._internal(
        (ref) => create(ref as PersonAssetsRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        personId: personId,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<RenderList> createElement() {
    return _PersonAssetsProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is PersonAssetsProvider && other.personId == personId;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, personId.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin PersonAssetsRef on AutoDisposeFutureProviderRef<RenderList> {
  /// The parameter `personId` of this provider.
  String get personId;
}

class _PersonAssetsProviderElement
    extends AutoDisposeFutureProviderElement<RenderList>
    with PersonAssetsRef {
  _PersonAssetsProviderElement(super.provider);

  @override
  String get personId => (origin as PersonAssetsProvider).personId;
}

String _$updatePersonNameHash() => r'45f7693172de522a227406d8198811434cf2bbbc';

/// See also [updatePersonName].
@ProviderFor(updatePersonName)
const updatePersonNameProvider = UpdatePersonNameFamily();

/// See also [updatePersonName].
class UpdatePersonNameFamily extends Family<AsyncValue<bool>> {
  /// See also [updatePersonName].
  const UpdatePersonNameFamily();

  /// See also [updatePersonName].
  UpdatePersonNameProvider call(String personId, String updatedName) {
    return UpdatePersonNameProvider(personId, updatedName);
  }

  @override
  UpdatePersonNameProvider getProviderOverride(
    covariant UpdatePersonNameProvider provider,
  ) {
    return call(provider.personId, provider.updatedName);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'updatePersonNameProvider';
}

/// See also [updatePersonName].
class UpdatePersonNameProvider extends AutoDisposeFutureProvider<bool> {
  /// See also [updatePersonName].
  UpdatePersonNameProvider(String personId, String updatedName)
    : this._internal(
        (ref) =>
            updatePersonName(ref as UpdatePersonNameRef, personId, updatedName),
        from: updatePersonNameProvider,
        name: r'updatePersonNameProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$updatePersonNameHash,
        dependencies: UpdatePersonNameFamily._dependencies,
        allTransitiveDependencies:
            UpdatePersonNameFamily._allTransitiveDependencies,
        personId: personId,
        updatedName: updatedName,
      );

  UpdatePersonNameProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.personId,
    required this.updatedName,
  }) : super.internal();

  final String personId;
  final String updatedName;

  @override
  Override overrideWith(
    FutureOr<bool> Function(UpdatePersonNameRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: UpdatePersonNameProvider._internal(
        (ref) => create(ref as UpdatePersonNameRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        personId: personId,
        updatedName: updatedName,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<bool> createElement() {
    return _UpdatePersonNameProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is UpdatePersonNameProvider &&
        other.personId == personId &&
        other.updatedName == updatedName;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, personId.hashCode);
    hash = _SystemHash.combine(hash, updatedName.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin UpdatePersonNameRef on AutoDisposeFutureProviderRef<bool> {
  /// The parameter `personId` of this provider.
  String get personId;

  /// The parameter `updatedName` of this provider.
  String get updatedName;
}

class _UpdatePersonNameProviderElement
    extends AutoDisposeFutureProviderElement<bool>
    with UpdatePersonNameRef {
  _UpdatePersonNameProviderElement(super.provider);

  @override
  String get personId => (origin as UpdatePersonNameProvider).personId;
  @override
  String get updatedName => (origin as UpdatePersonNameProvider).updatedName;
}

String _$mergePersonHash() => r'390307b239482d2f6574f942a566ce02e119c746';

/// See also [mergePerson].
@ProviderFor(mergePerson)
const mergePersonProvider = MergePersonFamily();

/// See also [mergePerson].
class MergePersonFamily extends Family<AsyncValue<bool>> {
  /// See also [mergePerson].
  const MergePersonFamily();

  /// See also [mergePerson].
  MergePersonProvider call(String personId, List<String> ids) {
    return MergePersonProvider(personId, ids);
  }

  @override
  MergePersonProvider getProviderOverride(
    covariant MergePersonProvider provider,
  ) {
    return call(provider.personId, provider.ids);
  }

  static const Iterable<ProviderOrFamily>? _dependencies = null;

  @override
  Iterable<ProviderOrFamily>? get dependencies => _dependencies;

  static const Iterable<ProviderOrFamily>? _allTransitiveDependencies = null;

  @override
  Iterable<ProviderOrFamily>? get allTransitiveDependencies =>
      _allTransitiveDependencies;

  @override
  String? get name => r'mergePersonProvider';
}

/// See also [mergePerson].
class MergePersonProvider extends AutoDisposeFutureProvider<bool> {
  /// See also [mergePerson].
  MergePersonProvider(String personId, List<String> ids)
    : this._internal(
        (ref) => mergePerson(ref as MergePersonRef, personId, ids),
        from: mergePersonProvider,
        name: r'mergePersonProvider',
        debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
            ? null
            : _$mergePersonHash,
        dependencies: MergePersonFamily._dependencies,
        allTransitiveDependencies: MergePersonFamily._allTransitiveDependencies,
        personId: personId,
        ids: ids,
      );

  MergePersonProvider._internal(
    super._createNotifier, {
    required super.name,
    required super.dependencies,
    required super.allTransitiveDependencies,
    required super.debugGetCreateSourceHash,
    required super.from,
    required this.personId,
    required this.ids,
  }) : super.internal();

  final String personId;
  final List<String> ids;

  @override
  Override overrideWith(
    FutureOr<bool> Function(MergePersonRef provider) create,
  ) {
    return ProviderOverride(
      origin: this,
      override: MergePersonProvider._internal(
        (ref) => create(ref as MergePersonRef),
        from: from,
        name: null,
        dependencies: null,
        allTransitiveDependencies: null,
        debugGetCreateSourceHash: null,
        personId: personId,
        ids: ids,
      ),
    );
  }

  @override
  AutoDisposeFutureProviderElement<bool> createElement() {
    return _MergePersonProviderElement(this);
  }

  @override
  bool operator ==(Object other) {
    return other is MergePersonProvider &&
        other.personId == personId &&
        other.ids == ids;
  }

  @override
  int get hashCode {
    var hash = _SystemHash.combine(0, runtimeType.hashCode);
    hash = _SystemHash.combine(hash, personId.hashCode);
    hash = _SystemHash.combine(hash, ids.hashCode);

    return _SystemHash.finish(hash);
  }
}

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
mixin MergePersonRef on AutoDisposeFutureProviderRef<bool> {
  /// The parameter `personId` of this provider.
  String get personId;

  /// The parameter `ids` of this provider.
  List<String> get ids;
}

class _MergePersonProviderElement extends AutoDisposeFutureProviderElement<bool>
    with MergePersonRef {
  _MergePersonProviderElement(super.provider);

  @override
  String get personId => (origin as MergePersonProvider).personId;
  @override
  List<String> get ids => (origin as MergePersonProvider).ids;
}

// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
