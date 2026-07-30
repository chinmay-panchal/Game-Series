import 'package:flutter_test/flutter_test.dart';
import 'package:gadhabaazi/models/card_model.dart';
import 'package:gadhabaazi/models/enums/suit.dart';
import 'package:gadhabaazi/models/enums/rank.dart';
import 'package:gadhabaazi/models/player_model.dart';
import 'package:gadhabaazi/engine/rules/move_rules.dart';
import 'package:gadhabaazi/engine/rules/loser_rules.dart';
import 'package:gadhabaazi/engine/game_engine.dart';

void main() {
  group('MoveRules', () {
    final moveRules = MoveRules();

    test('canPlayCard returns true when playing same suit', () {
      final player = Player(id: 'p1', name: 'Player 1', hand: [
        PlayingCard(suit: Suit.spades, rank: Rank.two),
        PlayingCard(suit: Suit.hearts, rank: Rank.four),
      ]);
      final card = PlayingCard(suit: Suit.spades, rank: Rank.two);

      expect(moveRules.canPlayCard(player, card, Suit.spades), isTrue);
    });

    test('canPlayCard returns false if playing different suit but has matching suit', () {
      final player = Player(id: 'p1', name: 'Player 1', hand: [
        PlayingCard(suit: Suit.spades, rank: Rank.two),
        PlayingCard(suit: Suit.hearts, rank: Rank.four),
      ]);
      final card = PlayingCard(suit: Suit.hearts, rank: Rank.four);

      expect(moveRules.canPlayCard(player, card, Suit.spades), isFalse);
    });

    test('canPlayCard returns false if no matching suit (should trigger punishment)', () {
      final player = Player(id: 'p1', name: 'Player 1', hand: [
        PlayingCard(suit: Suit.diamonds, rank: Rank.two),
        PlayingCard(suit: Suit.hearts, rank: Rank.four),
      ]);
      final card = PlayingCard(suit: Suit.hearts, rank: Rank.four);

      expect(moveRules.canPlayCard(player, card, Suit.spades), isFalse);
    });
  });

  group('LoserRules', () {
    final loserRules = LoserRules();

    test('isGameOver correctly detects game end', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: []);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.ace)]);

      expect(loserRules.isGameOver([p1, p2]), isTrue);
      expect(loserRules.donkeyPlayerId([p1, p2]), 'p2');
    });

    test('isGameOver is false when multiple players have cards', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: [PlayingCard(suit: Suit.hearts, rank: Rank.two)]);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.ace)]);

      expect(loserRules.isGameOver([p1, p2]), isFalse);
      expect(loserRules.donkeyPlayerId([p1, p2]), isNull);
    });

    test('finishedPlayerIds returns correct ids', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: []);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.ace)]);
      final p3 = Player(id: 'p3', name: 'P3', hand: []);

      expect(loserRules.finishedPlayerIds([p1, p2, p3]), equals(['p1', 'p3']));
    });
  });

  group('PunishmentRules Engine Test', () {
    test('punishment sweeps all played table cards + punishment card to target player', () {
      final engine = GameEngine();
      final res = engine.startGame(['P1', 'P2', 'P3']);
      var state = res.gameState;

      // Find who has Ace of Spades (P1 or P2 or P3)
      final starterIdx = state.activePlayerIndex;
      final starterId = state.players[starterIdx].id;

      // Starter plays Ace of Spades
      final aceSpades = PlayingCard(suit: Suit.spades, rank: Rank.ace);
      final playRes = engine.playCard(state, starterId, aceSpades);
      state = playRes.gameState;

      // Next player has no spades (we simulate hand update for test)
      final nextIdx = state.activePlayerIndex;
      final nextId = state.players[nextIdx].id;
      final punishCard = state.players[nextIdx].hand.firstWhere((c) => c.suit != Suit.spades);

      final giveRes = engine.givePunishment(state, nextId, punishCard);
      final finalState = giveRes.gameState;

      final starterPlayer = finalState.players.firstWhere((p) => p.id == starterId);
      // Starter should have original hand - 1 (played Ace) + 1 (Ace returned/swept back) + 1 (punishment card)
      expect(starterPlayer.hand.contains(aceSpades), isTrue);
      expect(starterPlayer.hand.contains(punishCard), isTrue);
    });
  });
}
