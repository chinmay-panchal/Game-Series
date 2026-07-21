import 'package:equatable/equatable.dart';
import 'card_model.dart';

class Player extends Equatable {
  final String id;
  final String name;
  final List<PlayingCard> hand;

  const Player({
    required this.id,
    required this.name,
    this.hand = const [],
  });

  Player copyWith({
    String? id,
    String? name,
    List<PlayingCard>? hand,
  }) {
    return Player(
      id: id ?? this.id,
      name: name ?? this.name,
      hand: hand ?? this.hand,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'hand': hand.map((c) => c.toJson()).toList(),
  };

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String,
      name: json['name'] as String,
      hand: (json['hand'] as List<dynamic>)
          .map((c) => PlayingCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  @override
  List<Object?> get props => [id, name, hand];
}
