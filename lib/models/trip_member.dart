class TripMember {
  final String id;
  final String name;
  final String? avatarUrl;
  final bool isCurrentUser;

  const TripMember({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.isCurrentUser = false,
  });

  TripMember copyWith({
    String? id,
    String? name,
    String? avatarUrl,
    bool? isCurrentUser,
  }) {
    return TripMember(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'isCurrentUser': isCurrentUser,
    };
  }

  factory TripMember.fromJson(Map<String, dynamic> json) {
    return TripMember(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      isCurrentUser: json['isCurrentUser'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TripMember && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'TripMember(id: $id, name: $name, isCurrentUser: $isCurrentUser)';
}
