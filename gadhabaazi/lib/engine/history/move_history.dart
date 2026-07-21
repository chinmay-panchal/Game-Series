import 'package:equatable/equatable.dart';

class MoveEntry extends Equatable {
  final DateTime timestamp;
  final String playerId;
  final String description;

  const MoveEntry({
    required this.timestamp,
    required this.playerId,
    required this.description,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'playerId': playerId,
    'description': description,
  };

  factory MoveEntry.fromJson(Map<String, dynamic> json) {
    return MoveEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      playerId: json['playerId'] as String,
      description: json['description'] as String,
    );
  }

  @override
  List<Object?> get props => [timestamp, playerId, description];
}

class MoveHistory extends Equatable {
  final List<MoveEntry> entries;

  const MoveHistory({this.entries = const []});

  MoveHistory record(String playerId, String description) {
    return MoveHistory(
      entries: [
        ...entries,
        MoveEntry(
          timestamp: DateTime.now(),
          playerId: playerId,
          description: description,
        ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory MoveHistory.fromJson(Map<String, dynamic> json) {
    return MoveHistory(
      entries: (json['entries'] as List<dynamic>)
          .map((e) => MoveEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [entries];
}
