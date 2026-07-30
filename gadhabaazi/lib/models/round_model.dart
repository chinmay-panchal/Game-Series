import 'package:equatable/equatable.dart';
import 'enums/suit.dart';
import 'played_card.dart';
import 'card_model.dart';

class RoundModel extends Equatable {
  final int roundNumber;
  final Suit suit;
  final String leadPlayerId;
  final List<PlayedCard> playedCards;
  final String? winnerId;
  final PlayingCard? punishmentCard;

  const RoundModel({
    required this.roundNumber,
    required this.suit,
    required this.leadPlayerId,
    this.playedCards = const [],
    this.winnerId,
    this.punishmentCard,
  });

  RoundModel copyWith({
    int? roundNumber,
    Suit? suit,
    String? leadPlayerId,
    List<PlayedCard>? playedCards,
    String? winnerId,
    PlayingCard? punishmentCard,
  }) {
    return RoundModel(
      roundNumber: roundNumber ?? this.roundNumber,
      suit: suit ?? this.suit,
      leadPlayerId: leadPlayerId ?? this.leadPlayerId,
      playedCards: playedCards ?? this.playedCards,
      winnerId: winnerId ?? this.winnerId,
      punishmentCard: punishmentCard ?? this.punishmentCard,
    );
  }

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'suit': suit.name,
    'leadPlayerId': leadPlayerId,
    'playedCards': playedCards.map((c) => c.toJson()).toList(),
    'winnerId': winnerId,
  };

  factory RoundModel.fromJson(Map<String, dynamic> json) {
    return RoundModel(
      roundNumber: json['roundNumber'] as int,
      suit: Suit.values.firstWhere((e) => e.name == json['suit']),
      leadPlayerId: json['leadPlayerId'] as String,
      playedCards: (json['playedCards'] as List?)
          ?.map((e) => PlayedCard.fromJson(e))
          .toList() ?? [],
      winnerId: json['winnerId'] as String?,
      punishmentCard: json['punishmentCard'] != null 
          ? PlayingCard.fromJson(json['punishmentCard']) 
          : null,
    );
  }

  @override
  List<Object?> get props => [roundNumber, suit, leadPlayerId, playedCards, winnerId, punishmentCard];
}
