import 'package:flutter_test/flutter_test.dart';
import 'package:gadhabaazi/models/card_model.dart';
import 'package:gadhabaazi/models/enums/suit.dart';
import 'package:gadhabaazi/models/enums/rank.dart';
import 'package:gadhabaazi/models/enums/game_phase.dart';
import 'package:gadhabaazi/models/player_model.dart';
import 'package:gadhabaazi/models/round_model.dart';
import 'package:gadhabaazi/models/played_card.dart';
import 'package:gadhabaazi/engine/history/move_history.dart';
import 'package:gadhabaazi/engine/rules/move_rules.dart';
import 'package:gadhabaazi/engine/rules/loser_rules.dart';
import 'package:gadhabaazi/engine/game_engine.dart';
import 'package:gadhabaazi/engine/game_state.dart';
import 'package:gadhabaazi/engine/move_result.dart';

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

  group('Unending Loop Detection (3 Rounds)', () {
    test('detects loop when total cards <= 4 remains constant for 3 rounds', () {
      final engine = GameEngine();

      // p1 has Spades and Clubs
      // p2 has Hearts and Diamonds
      // Neither shares a suit, guaranteeing reciprocal punishments without emptying hands
      final p1 = Player(id: 'p1', name: 'Player 1', hand: [
        PlayingCard(suit: Suit.spades, rank: Rank.ace),
        PlayingCard(suit: Suit.clubs, rank: Rank.two),
      ]);
      final p2 = Player(id: 'p2', name: 'Player 2', hand: [
        PlayingCard(suit: Suit.hearts, rank: Rank.ace),
        PlayingCard(suit: Suit.diamonds, rank: Rank.two),
      ]);

      var state = GameState(
        players: [p1, p2],
        activePlayerIndex: 0,
        phase: GamePhase.playerTurn,
        lastTotalCardsCount: 4, // 4 cards in play at the start of loop evaluation
      );

      // --- Round 1 ---
      // p1 leads ♠A
      var res = engine.playCard(state, 'p1', PlayingCard(suit: Suit.spades, rank: Rank.ace));
      expect(res.moveType, MoveType.cardPlayed);
      state = res.gameState;

      // Advance turn to p2
      res = engine.continueAfterTransition(state);
      state = res.gameState;
      expect(state.activePlayerIndex, 1);

      // p2 has no spades, gives punishment ♥A
      res = engine.givePunishment(state, 'p2', PlayingCard(suit: Suit.hearts, rank: Rank.ace));
      expect(res.moveType, isNot(MoveType.invalidMove), reason: res.message);
      state = res.gameState;

      // Round 1 ended. Total cards is still 4 (<= 4).
      expect(state.unendingLoopCounter, 1);
      expect(state.unendingLoopDetected, isFalse);

      // Transition to next round (p2 leads because p2 gave punishment)
      res = engine.continueAfterTransition(state);
      state = res.gameState;
      expect(state.activePlayerIndex, 1);

      // --- Round 2 ---
      // p2 leads ♦2
      res = engine.playCard(state, 'p2', PlayingCard(suit: Suit.diamonds, rank: Rank.two));
      expect(res.moveType, MoveType.cardPlayed);
      state = res.gameState;

      // Advance turn to p1
      res = engine.continueAfterTransition(state);
      state = res.gameState;
      expect(state.activePlayerIndex, 0);

      // p1 has [♣2, ♠A, ♥A], no diamonds! Gives punishment ♣2
      res = engine.givePunishment(state, 'p1', PlayingCard(suit: Suit.clubs, rank: Rank.two));
      expect(res.moveType, isNot(MoveType.invalidMove), reason: res.message);
      state = res.gameState;

      // Round 2 ended. Total cards is STILL 4 (<= 4).
      expect(state.unendingLoopCounter, 2);
      expect(state.unendingLoopDetected, isFalse);

      // Transition to next round (p1 leads because p1 gave punishment)
      res = engine.continueAfterTransition(state);
      state = res.gameState;
      expect(state.activePlayerIndex, 0);

      // --- Round 3 ---
      // p1 leads ♠A
      res = engine.playCard(state, 'p1', PlayingCard(suit: Suit.spades, rank: Rank.ace));
      expect(res.moveType, MoveType.cardPlayed);
      state = res.gameState;

      // Advance turn to p2
      res = engine.continueAfterTransition(state);
      state = res.gameState;
      expect(state.activePlayerIndex, 1);

      // p2 has [♦2, ♣2], no spades! Gives punishment ♦2
      res = engine.givePunishment(state, 'p2', PlayingCard(suit: Suit.diamonds, rank: Rank.two));
      expect(res.moveType, isNot(MoveType.invalidMove), reason: res.message);
      state = res.gameState;

      // Round 3 ended. Total cards is STILL 4 (<= 4).
      // Reached 3 rounds -> unendingLoopDetected is true!
      expect(state.unendingLoopCounter, 3);
      expect(state.unendingLoopDetected, isTrue);
    });
  });

  group('GameEngine - Player Disconnection and Card Redistribution', () {
    final engine = GameEngine();

    test('distributes disconnected player cards clockwisely to remaining players', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: [
        PlayingCard(suit: Suit.spades, rank: Rank.two),
      ]);
      final p2 = Player(id: 'p2', name: 'P2', hand: [
        PlayingCard(suit: Suit.hearts, rank: Rank.ace),
        PlayingCard(suit: Suit.diamonds, rank: Rank.king),
      ]);
      final p3 = Player(id: 'p3', name: 'P3', hand: [
        PlayingCard(suit: Suit.clubs, rank: Rank.three),
      ]);

      final state = GameState(
        players: [p1, p2, p3],
        activePlayerIndex: 1,
        phase: GamePhase.playerTurn,
        history: MoveHistory(),
      );

      // p2 disconnects. Hand has 2 cards: Ace of Hearts, King of Diamonds.
      // Clockwise next is p3, then p1.
      final result = engine.redistributePlayerCards(state, 'p2');
      final updatedPlayers = result.gameState.players;

      // p2 hand is now empty
      expect(updatedPlayers[1].hand, isEmpty);

      // p3 gets 1st card (Ace of Hearts or King of Diamonds) -> 2 cards total
      expect(updatedPlayers[2].hand.length, 2);

      // p1 gets 2nd card -> 2 cards total
      expect(updatedPlayers[0].hand.length, 2);
    });

    test('when disconnected player had highest rank card, next clockwise player gets lead', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: [PlayingCard(suit: Suit.spades, rank: Rank.two)]);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.three)]);
      final p3 = Player(id: 'p3', name: 'P3', hand: [PlayingCard(suit: Suit.spades, rank: Rank.four)]);

      final playedP1 = PlayedCard(playerId: 'p1', card: PlayingCard(suit: Suit.spades, rank: Rank.five));
      final playedP2 = PlayedCard(playerId: 'p2', card: PlayingCard(suit: Suit.spades, rank: Rank.ace)); // highest!

      final round = RoundModel(
        roundNumber: 1,
        suit: Suit.spades,
        leadPlayerId: 'p1',
        playedCards: [playedP1, playedP2],
      );

      final state = GameState(
        players: [p1, p2, p3],
        activePlayerIndex: 2,
        currentRound: round,
        phase: GamePhase.playerTurn,
        history: MoveHistory(),
      );

      // p2 (who played Ace) disconnects
      final result = engine.redistributePlayerCards(state, 'p2');

      // Next clockwise after p2 is p3 (index 2)
      expect(result.gameState.activePlayerIndex, 2);
      expect(result.gameState.currentRound, isNotNull);
      expect(result.gameState.currentRound!.playedCards.length, 2);
    });

    test('when leader plays Ace of Spades and leaves, Ace remains on table and next clockwise player takes turn', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: [PlayingCard(suit: Suit.hearts, rank: Rank.two)]);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.three)]);
      final p3 = Player(id: 'p3', name: 'P3', hand: [PlayingCard(suit: Suit.spades, rank: Rank.four)]);

      final playedP1 = PlayedCard(playerId: 'p1', card: PlayingCard(suit: Suit.spades, rank: Rank.ace));

      final round = RoundModel(
        roundNumber: 1,
        suit: Suit.spades,
        leadPlayerId: 'p1',
        playedCards: [playedP1],
      );

      final state = GameState(
        players: [p1, p2, p3],
        activePlayerIndex: 1, // P2's turn
        currentRound: round,
        phase: GamePhase.playerTurn,
        history: MoveHistory(),
      );

      final result = engine.redistributePlayerCards(state, 'p1');

      // Round MUST still be active and Ace of Spades MUST remain on table!
      expect(result.gameState.currentRound, isNotNull);
      expect(result.gameState.currentRound!.playedCards.length, 1);
      expect(result.gameState.currentRound!.playedCards.first.card.rank, Rank.ace);
      expect(result.gameState.currentRound!.playedCards.first.card.suit, Suit.spades);

      // P1 hand is emptied and given to P2 (clockwise)
      expect(result.gameState.players[0].hand, isEmpty);
      expect(result.gameState.players[1].hand.length, 2);

      // Next active player is P2
      expect(result.gameState.activePlayerIndex, 1);
    });

    test('when disconnected player had not played card, next clockwise player plays next', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: [PlayingCard(suit: Suit.spades, rank: Rank.two)]);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.three)]);
      final p3 = Player(id: 'p3', name: 'P3', hand: [PlayingCard(suit: Suit.spades, rank: Rank.four)]);

      // Only p1 has played so far
      final playedP1 = PlayedCard(playerId: 'p1', card: PlayingCard(suit: Suit.spades, rank: Rank.five));
      final round = RoundModel(
        roundNumber: 1,
        suit: Suit.spades,
        leadPlayerId: 'p1',
        playedCards: [playedP1],
      );

      final state = GameState(
        players: [p1, p2, p3],
        activePlayerIndex: 1, // It was p2's turn
        currentRound: round,
        phase: GamePhase.playerTurn,
        history: MoveHistory(),
      );

      // p2 disconnects before playing
      final result = engine.redistributePlayerCards(state, 'p2');

      // Next clockwise player who hasn't played is p3 (index 2)
      expect(result.gameState.activePlayerIndex, 2);
    });

    test('if only 1 player remains after disconnect, game ends and remaining player wins', () {
      final p1 = Player(id: 'p1', name: 'P1', hand: [PlayingCard(suit: Suit.spades, rank: Rank.two)]);
      final p2 = Player(id: 'p2', name: 'P2', hand: [PlayingCard(suit: Suit.spades, rank: Rank.three)]);

      final state = GameState(
        players: [p1, p2],
        activePlayerIndex: 1,
        phase: GamePhase.playerTurn,
        history: MoveHistory(),
      );

      final result = engine.redistributePlayerCards(state, 'p2');
      expect(result.gameState.phase, GamePhase.gameOver);
      expect(result.gameState.donkeyPlayerId, 'p2');
      expect(result.gameState.finishedPlayerIds.first, 'p1');
    });
  });
}

