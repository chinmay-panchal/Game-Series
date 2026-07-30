import '../../models/card_model.dart';
import '../../models/player_model.dart';
import '../../models/played_card.dart';
import '../../models/round_model.dart';
import '../../models/enums/game_phase.dart';
import '../../models/enums/suit.dart';
import '../../models/enums/rank.dart';
import 'game_state.dart';
import 'move_result.dart';
import 'rules/move_rules.dart';
import 'rules/punishment_rules.dart';
import 'rules/loser_rules.dart';
import 'deck_builder.dart';
import 'history/move_history.dart';

class GameEngine {
  final MoveRules _moveRules = MoveRules();
  final PunishmentRules _punishmentRules = PunishmentRules();
  final LoserRules _loserRules = LoserRules();

  MoveResult startGame(List<String> playerNames) {
    List<PlayingCard> deck = DeckBuilder.buildDeck();
    DeckBuilder.shuffle(deck);

    List<Player> players = playerNames.asMap().entries.map((entry) {
      return Player(id: 'p${entry.key}', name: entry.value, hand: []);
    }).toList();

    // Distribute cards one by one
    int currentPlayerIndex = 0;
    while (deck.isNotEmpty) {
      players[currentPlayerIndex] = players[currentPlayerIndex].copyWith(
        hand: [...players[currentPlayerIndex].hand, deck.removeLast()],
      );
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    }

    // Sort hands for better UX
    for (int i = 0; i < players.length; i++) {
      List<PlayingCard> sortedHand = List.from(players[i].hand);
      sortedHand.sort((a, b) {
        if (a.suit.index != b.suit.index)
          return a.suit.index.compareTo(b.suit.index);
        return a.rank.index.compareTo(b.rank.index); // Ascending order
      });
      players[i] = players[i].copyWith(hand: sortedHand);
    }

    // Find the player with Ace of Spades
    int starterIndex = 0;
    for (int i = 0; i < players.length; i++) {
      if (players[i].hand.any(
        (c) => c.suit == Suit.spades && c.rank == Rank.ace,
      )) {
        starterIndex = i;
        break;
      }
    }

    MoveHistory history = const MoveHistory();
    history = history.record(
      'system',
      'Game started with ${players.length} players.',
    );
    history = history.record(
      players[starterIndex].id,
      'Has Ace of Spades, starts the game.',
    );

    final initialState = GameState(
      players: players,
      activePlayerIndex: starterIndex,
      phase: GamePhase.dealing,
      history: history,
    );

    return MoveResult(
      gameState: initialState,
      moveType: MoveType
          .cardPlayed, // Initial state, but let UI transition from dealing to playerTurn
    );
  }

  MoveResult playCard(GameState state, String playerId, PlayingCard card) {
    if (state.players[state.activePlayerIndex].id != playerId) {
      return MoveResult(
        gameState: state,
        moveType: MoveType.invalidMove,
        message: "Not your turn",
      );
    }

    Player activePlayer = state.players[state.activePlayerIndex];

    // Check if player actually has the card
    if (!activePlayer.hand.contains(card)) {
      return MoveResult(
        gameState: state,
        moveType: MoveType.invalidMove,
        message: "You don't own this card",
      );
    }

    RoundModel currentRound =
        state.currentRound ??
        RoundModel(
          roundNumber: state.completedRounds.length + 1,
          suit: card.suit,
          leadPlayerId: playerId,
          playedCards: [],
        );

    if (currentRound.playedCards.isNotEmpty) {
      bool canPlay = _moveRules.canPlayCard(
        activePlayer,
        card,
        currentRound.suit,
      );
      if (!canPlay) {
        if (_moveRules.mustPunish(activePlayer, currentRound.suit)) {
          return MoveResult(
            gameState: state.copyWith(phase: GamePhase.punishmentSelection),
            moveType: MoveType.punishmentRequired,
            message: "You must give a punishment card!",
          );
        }
        return MoveResult(
          gameState: state,
          moveType: MoveType.invalidMove,
          message: "You must follow the current suit!",
        );
      }
    }

    // Special rule for first round: MUST play Ace of Spades if they have it and it's the first card
    if (state.completedRounds.isEmpty && currentRound.playedCards.isEmpty) {
      if (card.suit != Suit.spades || card.rank != Rank.ace) {
        return MoveResult(
          gameState: state,
          moveType: MoveType.invalidMove,
          message: "You must start with the Ace of Spades!",
        );
      }
    }

    // Play the card
    List<PlayingCard> newHand = List.from(activePlayer.hand)..remove(card);
    Player updatedPlayer = activePlayer.copyWith(hand: newHand);
    List<Player> newPlayers = List.from(state.players)
      ..[state.activePlayerIndex] = updatedPlayer;

    final playedCard = PlayedCard(playerId: playerId, card: card);
    currentRound = currentRound.copyWith(
      playedCards: [...currentRound.playedCards, playedCard],
    );

    MoveHistory newHistory = state.history.record(
      playerId,
      "Played ${card.suit.symbol}${card.rank.label}",
    );

    GameState newState = state.copyWith(
      players: newPlayers,
      currentRound: currentRound,
      history: newHistory,
    );

    // Check if round is over. A player is in this round if they have cards OR they have already played a card in this round.
    int playersInThisRound = newPlayers
        .where(
          (p) =>
              p.hand.isNotEmpty ||
              currentRound!.playedCards.any((c) => c.playerId == p.id),
        )
        .length;

    if (currentRound.playedCards.length == playersInThisRound ||
        currentRound.playedCards.length == newPlayers.length) {
      // Round completed
      return _completeRound(newState);
    }

    return MoveResult(
      gameState: newState.copyWith(phase: GamePhase.turnTransition),
      moveType: MoveType.cardPlayed,
    );
  }

  MoveResult _completeRound(GameState state) {
    final roundLeaderId = _moveRules.roundLeaderId(state.currentRound!);
    final newHistory = state.history.record(
      'system',
      "Round ${state.currentRound!.roundNumber} complete. $roundLeaderId leads next round.",
    );

    List<String> newFinishedPlayers = List.from(state.finishedPlayerIds);
    // Check for newly finished players
    for (var p in state.players) {
      if (p.hand.isEmpty && !newFinishedPlayers.contains(p.id)) {
        newFinishedPlayers.add(p.id);
      }
    }

    final newState = state.copyWith(
      completedRounds: [...state.completedRounds, state.currentRound!],
      clearCurrentRound: true,
      history: newHistory,
      finishedPlayerIds: newFinishedPlayers,
    );

    if (_loserRules.isGameOver(newState.players)) {
      final donkeyId = _loserRules.donkeyPlayerId(newState.players);
      final finalHistory = newState.history.record(
        'system',
        'Game Over. Donkey is $donkeyId',
      );

      return MoveResult(
        gameState: newState.copyWith(
          phase: GamePhase.gameOver,
          donkeyPlayerId: donkeyId,
          history: finalHistory,
        ),
        moveType: MoveType.gameCompleted,
      );
    }

    int unendingLoopCounter = state.unendingLoopCounter;
    int lastTotalCardsCount = state.lastTotalCardsCount;
    bool unendingLoopDetected = state.unendingLoopDetected;

    // Unending loop detection for 2-player games
    if (newState.players.length == 2 && !newState.finishedPlayerIds.contains(newState.players[0].id) && !newState.finishedPlayerIds.contains(newState.players[1].id)) {
      int currentTotalCards = newState.players[0].hand.length + newState.players[1].hand.length;
      if (currentTotalCards == lastTotalCardsCount) {
        unendingLoopCounter++;
      } else {
        unendingLoopCounter = 0;
        lastTotalCardsCount = currentTotalCards;
      }
      
      if (unendingLoopCounter >= 3) {
        unendingLoopDetected = true;
      }
    }

    return MoveResult(
      gameState: newState.copyWith(
        phase: GamePhase.roundEnd,
        unendingLoopCounter: unendingLoopCounter,
        lastTotalCardsCount: lastTotalCardsCount,
        unendingLoopDetected: unendingLoopDetected,
      ),
      moveType: MoveType.roundCompleted,
    );
  }

  /// Breaks an unending loop by distributing up to 5 cards randomly to each of the two players
  /// from the previously played cards (completed rounds).
  MoveResult distributeNewCards(GameState state) {
    if (!state.unendingLoopDetected || state.players.length != 2) {
      return MoveResult(
        gameState: state,
        moveType: MoveType.invalidMove,
        message: "Cannot distribute cards right now",
      );
    }

    // 1. Collect cards ONLY from normal completed rounds (exclude punishment rounds)
    List<PlayingCard> pool = [];
    for (var round in state.completedRounds) {
      if (round.punishmentCard != null) continue; // Punishment cards returned to players
      for (var playedCard in round.playedCards) {
        pool.add(playedCard.card);
      }
    }

    // 2. Filter out any card that is currently in ANY player's hand
    Set<PlayingCard> currentHandsCards = {};
    for (var player in state.players) {
      currentHandsCards.addAll(player.hand);
    }
    pool.removeWhere((c) => currentHandsCards.contains(c));

    // Deduplicate pool
    pool = pool.toSet().toList();

    if (pool.isEmpty) {
      return MoveResult(
        gameState: state,
        moveType: MoveType.invalidMove,
        message: "No available discarded cards to distribute.",
      );
    }

    DeckBuilder.shuffle(pool);

    List<Player> newPlayers = List.from(state.players);

    // Distribute up to 5 cards to each player
    int cardsToGive = pool.length >= 10 ? 5 : pool.length ~/ 2;
    if (cardsToGive == 0 && pool.isNotEmpty) cardsToGive = 1;

    for (int i = 0; i < 2; i++) {
      List<PlayingCard> newHand = List.from(newPlayers[i].hand);
      for (int c = 0; c < cardsToGive; c++) {
        if (pool.isNotEmpty) {
          newHand.add(pool.removeLast());
        }
      }
      // Re-sort the hand
      newHand.sort((a, b) {
        if (a.suit.index != b.suit.index) {
          return a.suit.index.compareTo(b.suit.index);
        }
        return a.rank.index.compareTo(b.rank.index);
      });
      newPlayers[i] = newPlayers[i].copyWith(hand: newHand);
    }

    MoveHistory newHistory = state.history.record(
      'system',
      'Unending loop resolved: Distributed $cardsToGive new cards to both players.',
    );

    return MoveResult(
      gameState: state.copyWith(
        players: newPlayers,
        history: newHistory,
        unendingLoopCounter: 0,
        unendingLoopDetected: false,
      ),
      moveType: MoveType.cardPlayed,
    );
  }

  MoveResult givePunishment(GameState state, String giverId, PlayingCard card) {
    if (state.players[state.activePlayerIndex].id != giverId) {
      return MoveResult(
        gameState: state,
        moveType: MoveType.invalidMove,
        message: "Not your turn",
      );
    }

    Player giver = state.players[state.activePlayerIndex];
    if (!giver.hand.contains(card)) {
      return MoveResult(
        gameState: state,
        moveType: MoveType.invalidMove,
        message: "It's not your turn",
      );
    }

    // Find who holds the highest card — they receive the punishment card
    String targetId = _punishmentRules.targetOfPunishment(
      state.currentRound!.playedCards,
    );
    int targetIndex = state.players.indexWhere((p) => p.id == targetId);

    // Start with a mutable copy of all players
    List<Player> newPlayers = List.from(state.players);

    // Step 1: Collect all cards played on the table during this round
    List<PlayingCard> tableCards = state.currentRound!.playedCards
        .map((p) => p.card)
        .toList();

    // Step 2: Remove the punishment card from the giver's hand
    int giverIndex = newPlayers.indexWhere((p) => p.id == giverId);
    List<PlayingCard> newGiverHand = List.from(newPlayers[giverIndex].hand)
      ..remove(card);
    newPlayers[giverIndex] = newPlayers[giverIndex].copyWith(
      hand: newGiverHand,
    );

    // Step 3: Give ALL table cards + punishment card to the target (highest card holder)
    List<PlayingCard> newTargetHand = List.from(newPlayers[targetIndex].hand)
      ..addAll(tableCards)
      ..add(card);
    newPlayers[targetIndex] = newPlayers[targetIndex].copyWith(
      hand: newTargetHand,
    );

    MoveHistory newHistory = state.history.record(
      giverId,
      "Gave punishment card to $targetId. All table cards collected by $targetId.",
    );

    // The giver of the punishment leads the next round
    GameState newState = state.copyWith(
      players: newPlayers,
      history: newHistory,
      currentRound: state.currentRound!.copyWith(
        winnerId: giverId,
        punishmentCard: card, // store so UI can show "you got punished with X"
      ),
    );

    return _completeRound(newState);
  }

  MoveResult continueAfterTransition(GameState state) {
    // Determine next valid active player
    // If it's a new round, the leader starts
    // If it's game over, do nothing

    if (state.phase == GamePhase.gameOver) {
      return MoveResult(gameState: state, moveType: MoveType.gameCompleted);
    }

    int nextIndex = state.activePlayerIndex;

    if (state.currentRound == null && state.completedRounds.isNotEmpty) {
      // Start of a new round, leader starts
      String leaderId = _moveRules.roundLeaderId(state.completedRounds.last);
      nextIndex = state.players.indexWhere((p) => p.id == leaderId);
    } else {
      // Advance to next active player
      nextIndex = (state.activePlayerIndex + 1) % state.players.length;
    }

    // Skip finished players
    while (!_loserRules.isActive(state.players[nextIndex])) {
      nextIndex = (nextIndex + 1) % state.players.length;
    }

    GameState newState = state.copyWith(
      activePlayerIndex: nextIndex,
      phase: GamePhase.playerTurn,
    );

    return MoveResult(
      gameState: newState,
      moveType: MoveType.cardPlayed, // Generic success for BLoC
    );
  }
}
