import 'package:equatable/equatable.dart';
import 'enums/suit.dart';
import 'enums/rank.dart';

class PlayingCard extends Equatable {
  final Suit suit;
  final Rank rank;

  const PlayingCard({
    required this.suit,
    required this.rank,
  });

  PlayingCard copyWith({
    Suit? suit,
    Rank? rank,
  }) {
    return PlayingCard(
      suit: suit ?? this.suit,
      rank: rank ?? this.rank,
    );
  }

  Map<String, dynamic> toJson() => {
    'suit': suit.name,
    'rank': rank.name,
  };

  factory PlayingCard.fromJson(Map<String, dynamic> json) {
    return PlayingCard(
      suit: Suit.values.firstWhere((e) => e.name == json['suit']),
      rank: Rank.values.firstWhere((e) => e.name == json['rank']),
    );
  }

  @override
  List<Object?> get props => [suit, rank];
}
