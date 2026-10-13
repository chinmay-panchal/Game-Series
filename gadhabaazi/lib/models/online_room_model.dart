/// Represents a player slot in an online room.
class OnlinePlayerModel {
  final String uid;
  final String name;
  final bool isOnline;
  final int joinedAt;
  final int lastSeen;

  final bool hasWon;

  const OnlinePlayerModel({
    required this.uid,
    required this.name,
    required this.isOnline,
    required this.joinedAt,
    this.lastSeen = 0,
    this.hasWon = false,
  });

  bool get isActive {
    if (!isOnline) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final effectiveLastSeen = lastSeen > 0 ? lastSeen : joinedAt;
    if (effectiveLastSeen > 0) {
      return (now - effectiveLastSeen) < 6000;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'isOnline': isOnline,
        'joinedAt': joinedAt,
        'lastSeen': lastSeen,
        'hasWon': hasWon,
      };

  factory OnlinePlayerModel.fromJson(String uid, Map<Object?, Object?> json) {
    return OnlinePlayerModel(
      uid: uid,
      name: json['name'] as String? ?? 'Unknown',
      isOnline: json['isOnline'] as bool? ?? false,
      joinedAt: json['joinedAt'] as int? ?? 0,
      lastSeen: json['lastSeen'] as int? ?? 0,
      hasWon: json['hasWon'] as bool? ?? false,
    );
  }

  OnlinePlayerModel copyWith({bool? isOnline, int? lastSeen, bool? hasWon}) {
    return OnlinePlayerModel(
      uid: uid,
      name: name,
      isOnline: isOnline ?? this.isOnline,
      joinedAt: joinedAt,
      lastSeen: lastSeen ?? this.lastSeen,
      hasWon: hasWon ?? this.hasWon,
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

  OnlineRoomModel copyWith({
    String? roomId,
    String? roomCode,
    String? hostId,
    String? status,
    int? maxPlayers,
    int? createdAt,
  }) {
    return OnlineRoomModel(
      roomId: roomId ?? this.roomId,
      roomCode: roomCode ?? this.roomCode,
      hostId: hostId ?? this.hostId,
      status: status ?? this.status,
      maxPlayers: maxPlayers ?? this.maxPlayers,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
