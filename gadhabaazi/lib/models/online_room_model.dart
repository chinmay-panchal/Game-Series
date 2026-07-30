/// Represents a player slot in an online room.
class OnlinePlayerModel {
  final String uid;
  final String name;
  final bool isOnline;
  final int joinedAt;

  const OnlinePlayerModel({
    required this.uid,
    required this.name,
    required this.isOnline,
    required this.joinedAt,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'isOnline': isOnline,
        'joinedAt': joinedAt,
      };

  factory OnlinePlayerModel.fromJson(String uid, Map<Object?, Object?> json) {
    return OnlinePlayerModel(
      uid: uid,
      name: json['name'] as String? ?? 'Unknown',
      isOnline: json['isOnline'] as bool? ?? false,
      joinedAt: json['joinedAt'] as int? ?? 0,
    );
  }

  OnlinePlayerModel copyWith({bool? isOnline}) {
    return OnlinePlayerModel(
      uid: uid,
      name: name,
      isOnline: isOnline ?? this.isOnline,
      joinedAt: joinedAt,
    );
  }
}

/// Metadata for an online game room.
class OnlineRoomModel {
  final String roomId;
  final String roomCode;
  final String hostId;
  final String status; // waiting | in_progress | completed
  final int maxPlayers;
  final int createdAt;

  const OnlineRoomModel({
    required this.roomId,
    required this.roomCode,
    required this.hostId,
    required this.status,
    required this.maxPlayers,
    required this.createdAt,
  });

  factory OnlineRoomModel.fromJson(String roomId, Map<Object?, Object?> json) {
    return OnlineRoomModel(
      roomId: roomId,
      roomCode: json['roomCode'] as String? ?? '',
      hostId: json['hostId'] as String? ?? '',
      status: json['status'] as String? ?? 'waiting',
      maxPlayers: json['maxPlayers'] as int? ?? 4,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'roomCode': roomCode,
        'hostId': hostId,
        'status': status,
        'maxPlayers': maxPlayers,
        'createdAt': createdAt,
      };
}
