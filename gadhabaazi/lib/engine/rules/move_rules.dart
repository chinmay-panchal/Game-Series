import '../../models/card_model.dart';
import '../../models/player_model.dart';
import '../../models/played_card.dart';
import '../../models/round_model.dart';
import '../../models/enums/suit.dart';

class MoveRules {
  /// Check if the player can play this card.
  /// If the player has at least one card of [currentSuit], they MUST play a card of [currentSuit].
  /// Otherwise, they should have triggered punishment, not playing a card normally.
  bool canPlayCard(Player player, PlayingCard card, Suit currentSuit) {
    if (card.suit == currentSuit) return true;
    
    // If the card is not of the current suit, we must check if the player has any cards of the current suit.
    bool hasMatchingSuit = player.hand.any((c) => c.suit == currentSuit);
    if (hasMatchingSuit) {
      return false; // Player MUST follow suit
    }
    
    // In Gadhabaazi, if they don't have the suit, they give a punishment.
    // That's handled via `givePunishment` flow, not `playCard`.
    return false;
  }

  bool mustPunish(Player player, Suit currentSuit) {
    return !player.hand.any((c) => c.suit == currentSuit);
  }

  PlayedCard? currentHighestCard(List<PlayedCard> playedCards) {
    if (playedCards.isEmpty) return null;
    
    PlayedCard highest = playedCards.first;
    // Note: This assumes playedCards only contain cards of the lead suit,
    // or we only compare within the lead suit.
    // In Gadhabaazi, only the lead suit counts for round leader.
    Suit leadSuit = highest.card.suit;
    
    for (int i = 1; i < playedCards.length; i++) {
      PlayedCard pc = playedCards[i];
      if (pc.card.suit == leadSuit && pc.card.rank.index > highest.card.rank.index) {
        highest = pc;
      }
    }
    return highest;
  }

  String roundLeaderId(RoundModel round) {
    if (round.winnerId != null) {
      return round.winnerId!;
    }
    
    final highest = currentHighestCard(round.playedCards);
    if (highest != null) {
      return highest.playerId;
    }
    return round.leadPlayerId;
  }
}
