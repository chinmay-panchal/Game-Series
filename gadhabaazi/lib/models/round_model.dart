import 'package:equatable/equatable.dart';
import 'enums/suit.dart';
import 'played_card.dart';

class RoundModel extends Equatable {
  final int roundNumber;
  final Suit suit;
  final String leadPlayerId;
  final List<PlayedCard> playedCards;
  final String? winnerId;

  const RoundModel({
    required this.roundNumber,
    required this.suit,
    required this.leadPlayerId,
    this.playedCards = const [],
    this.winnerId,
  });

  RoundModel copyWith({
    int? roundNumber,
    Suit? suit,
    String? leadPlayerId,
    List<PlayedCard>? playedCards,
    String? winnerId,
  }) {
    return RoundModel(
      roundNumber: roundNumber ?? this.roundNumber,
      suit: suit ?? this.suit,
      leadPlayerId: leadPlayerId ?? this.leadPlayerId,
      playedCards: playedCards ?? this.playedCards,
      winnerId: winnerId ?? this.winnerId,
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
      playedCards: (json['playedCards'] as List<dynamic>)
          .map((c) => PlayedCard.fromJson(c as Map<String, dynamic>))
          .toList(),
      winnerId: json['winnerId'] as String?,
    );
  }

  @override
  List<Object?> get props => [roundNumber, suit, leadPlayerId, playedCards, winnerId];
}
