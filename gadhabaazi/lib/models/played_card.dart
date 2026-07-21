import 'package:equatable/equatable.dart';
import 'card_model.dart';

/// Ties a card to the player who played it, enabling easy round-leader detection.
class PlayedCard extends Equatable {
  final String playerId;
  final PlayingCard card;

  const PlayedCard({
    required this.playerId,
    required this.card,
  });

  PlayedCard copyWith({
    String? playerId,
    PlayingCard? card,
  }) {
    return PlayedCard(
      playerId: playerId ?? this.playerId,
      card: card ?? this.card,
    );
  }

  Map<String, dynamic> toJson() => {
    'playerId': playerId,
    'card': card.toJson(),
  };

  factory PlayedCard.fromJson(Map<String, dynamic> json) {
    return PlayedCard(
      playerId: json['playerId'] as String,
      card: PlayingCard.fromJson(json['card'] as Map<String, dynamic>),
    );
  }

  @override
  List<Object?> get props => [playerId, card];
}
