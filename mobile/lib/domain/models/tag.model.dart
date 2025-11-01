class Tag {
  final String id;
  final String name;
  final String value;
  final String? color;
  final String? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Tag({
    required this.id,
    required this.name,
    required this.value,
    this.color,
    this.parentId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Tag.fromDto(dynamic dto) {
    return Tag(
      id: dto.id,
      name: dto.name,
      value: dto.value,
      color: dto.color,
      parentId: dto.parentId,
      createdAt: dto.createdAt,
      updatedAt: dto.updatedAt,
    );
  }

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as String,
      color: json['color'] as String?,
      parentId: json['parentId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'value': value,
    'color': color,
    'parentId': parentId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Tag &&
          id == other.id &&
          name == other.name &&
          value == other.value &&
          color == other.color &&
          parentId == other.parentId &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      value.hashCode ^
      color.hashCode ^
      parentId.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() =>
      'Tag(id: $id, name: $name, value: $value, color: $color, parentId: $parentId, createdAt: $createdAt, updatedAt: $updatedAt)';
} 