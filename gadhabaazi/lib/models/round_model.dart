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
  final List<PlayingCard>? punishmentCards;

  const RoundModel({
    required this.roundNumber,
    required this.suit,
    required this.leadPlayerId,
    this.playedCards = const [],
    this.winnerId,
    this.punishmentCard,
    this.punishmentCards,
  });

  RoundModel copyWith({
    int? roundNumber,
    Suit? suit,
    String? leadPlayerId,
    List<PlayedCard>? playedCards,
    String? winnerId,
    PlayingCard? punishmentCard,
    List<PlayingCard>? punishmentCards,
  }) {
    return RoundModel(
      roundNumber: roundNumber ?? this.roundNumber,
      suit: suit ?? this.suit,
      leadPlayerId: leadPlayerId ?? this.leadPlayerId,
      playedCards: playedCards ?? this.playedCards,
      winnerId: winnerId ?? this.winnerId,
      punishmentCard: punishmentCard ?? this.punishmentCard,
      punishmentCards: punishmentCards ?? this.punishmentCards,
    );
  }

  Map<String, dynamic> toJson() => {
    'roundNumber': roundNumber,
    'suit': suit.name,
    'leadPlayerId': leadPlayerId,
    'playedCards': playedCards.map((c) => c.toJson()).toList(),
    'winnerId': winnerId,
    if (punishmentCard != null) 'punishmentCard': punishmentCard!.toJson(),
    if (punishmentCards != null)
      'punishmentCards': punishmentCards!.map((c) => c.toJson()).toList(),
  };

  factory RoundModel.fromJson(Map<String, dynamic> json) {
    List<PlayingCard>? punishmentCards;
    if (json['punishmentCards'] != null) {
      punishmentCards = (json['punishmentCards'] as List?)
          ?.map((e) => PlayingCard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    PlayingCard? punishmentCard;
    if (json['punishmentCard'] != null) {
      punishmentCard = PlayingCard.fromJson(Map<String, dynamic>.from(json['punishmentCard'] as Map));
    } else if (punishmentCards != null && punishmentCards.isNotEmpty) {
      punishmentCard = punishmentCards.first;
    }

    return RoundModel(
      roundNumber: json['roundNumber'] as int,
      suit: Suit.values.firstWhere((e) => e.name == json['suit']),
      leadPlayerId: json['leadPlayerId'] as String,
      playedCards: (json['playedCards'] as List?)
          ?.map((e) => PlayedCard.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList() ?? [],
      winnerId: json['winnerId'] as String?,
      punishmentCard: punishmentCard,
      punishmentCards: punishmentCards,
    );
  }

  @override
  List<Object?> get props => [roundNumber, suit, leadPlayerId, playedCards, winnerId, punishmentCard, punishmentCards];
}
