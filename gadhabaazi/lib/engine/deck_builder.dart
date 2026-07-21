import '../../models/card_model.dart';
import '../../models/enums/suit.dart';
import '../../models/enums/rank.dart';
import 'dart:math';

class DeckBuilder {
  static List<PlayingCard> buildDeck() {
    List<PlayingCard> deck = [];
    for (var suit in Suit.values) {
      for (var rank in Rank.values) {
        deck.add(PlayingCard(suit: suit, rank: rank));
      }
    }
    return deck;
  }

  static void shuffle(List<PlayingCard> deck) {
    deck.shuffle(Random());
  }
}
