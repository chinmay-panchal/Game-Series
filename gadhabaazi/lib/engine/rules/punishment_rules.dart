import '../../models/played_card.dart';
import 'move_rules.dart';

class PunishmentRules {
  final MoveRules _moveRules = MoveRules();

  /// The punishment card goes to whoever currently holds the highest-ranked card
  /// of the lead suit in the current round.
  String targetOfPunishment(List<PlayedCard> playedCards) {
    if (playedCards.isEmpty) {
      throw StateError("Cannot punish when no cards have been played");
    }
    final highest = _moveRules.currentHighestCard(playedCards);
    return highest!.playerId;
  }
}
