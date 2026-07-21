import '../../models/player_model.dart';

class LoserRules {
  /// Returns true when only one player still has cards.
  bool isGameOver(List<Player> players) {
    return players.where((p) => p.hand.isNotEmpty).length == 1;
  }

  /// Returns the playerId of the sole remaining player with cards.
  String? donkeyPlayerId(List<Player> players) {
    final remaining = players.where((p) => p.hand.isNotEmpty).toList();
    if (remaining.length == 1) {
      return remaining.first.id;
    }
    return null;
  }

  /// Returns playerIds of players who have already emptied their hand.
  List<String> finishedPlayerIds(List<Player> players) {
    return players.where((p) => p.hand.isEmpty).map((p) => p.id).toList();
  }

  /// Returns true if this player is still active (has cards, not finished).
  bool isActive(Player player) {
    return player.hand.isNotEmpty;
  }
}
