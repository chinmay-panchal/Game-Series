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
              currentRound.playedCards.any((c) => c.playerId == p.id),
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
          phase: GamePhase.roundEnd, // Show last cards before game over
          donkeyPlayerId: donkeyId,
          history: finalHistory,
        ),
        moveType: MoveType.cardPlayed, // Treat as normal round end for now
      );
    }

    int unendingLoopCounter = state.unendingLoopCounter;
    int lastTotalCardsCount = state.lastTotalCardsCount;
    bool unendingLoopDetected = state.unendingLoopDetected;

    // Unending loop detection: only when 2 players remain with <= 4 total cards between them
    final activePlayers = newState.players.where((p) => !newState.finishedPlayerIds.contains(p.id)).toList();
    if (activePlayers.length == 2) {
      int currentTotalCards = activePlayers[0].hand.length + activePlayers[1].hand.length;
      // Only count towards redistribution when total cards are <= 4
      if (currentTotalCards <= 4 && currentTotalCards == lastTotalCardsCount) {
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
    final activePlayers = state.players.where((p) => !state.finishedPlayerIds.contains(p.id)).toList();
    if (!state.unendingLoopDetected || activePlayers.length != 2) {
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

    // Distribute up to 5 cards to each of the 2 active players
    int cardsToGive = pool.length >= 10 ? 5 : pool.length ~/ 2;
    if (cardsToGive == 0 && pool.isNotEmpty) cardsToGive = 1;

    for (int i = 0; i < 2; i++) {
      final activePlayer = activePlayers[i];
      final playerIdx = newPlayers.indexWhere((p) => p.id == activePlayer.id);
      if (playerIdx == -1) continue;
      
      List<PlayingCard> newHand = List.from(newPlayers[playerIdx].hand);
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
      newPlayers[playerIdx] = newPlayers[playerIdx].copyWith(hand: newHand);
    }

    MoveHistory newHistory = state.history.record(
      'system',
      'Unending loop resolved: Distributed $cardsToGive new cards to both remaining active players.',
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

    if (state.donkeyPlayerId != null) {
      return MoveResult(
        gameState: state.copyWith(phase: GamePhase.gameOver),
        moveType: MoveType.gameCompleted,
      );
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

  /// Removes a disconnected player and distributes their cards clockwise to remaining active players.
  ///
  /// Turn rules after removal:
  /// 1. If disconnected player had the highest rank card this round → clockwise next player leads.
  /// 2. If disconnected player hadn't played yet this round → clockwise next player takes their turn.
  /// 3. If disconnected player already played (not highest) → round checks for completion.
  /// 4. Distribution is one-by-one clockwise starting from the first player after disconnected player.
  MoveResult redistributePlayerCards(GameState state, String disconnectedPlayerId) {
    int discIdx = state.players.indexWhere((p) => p.id == disconnectedPlayerId);
    if (discIdx == -1) {
      return MoveResult(gameState: state, moveType: MoveType.cardPlayed);
    }

    final disconnectedPlayer = state.players[discIdx];
    final List<PlayingCard> cardsToDistribute = List.from(disconnectedPlayer.hand);

    // If player already finished cards or was marked finished, they have already won!
    // They cannot forfeit, cannot be the donkey, and have no cards to distribute.
    if (cardsToDistribute.isEmpty || state.finishedPlayerIds.contains(disconnectedPlayerId)) {
      return MoveResult(gameState: state, moveType: MoveType.cardPlayed);
    }

    List<Player> newPlayers = List.from(state.players);

    // Empty the disconnected player's hand
    newPlayers[discIdx] = newPlayers[discIdx].copyWith(hand: []);

    // Build clockwise-ordered list of active remaining player indices
    // starting from the player AFTER the disconnected player
    final int totalPlayers = newPlayers.length;
    List<int> clockwiseRemainingIndices = [];
    for (int offset = 1; offset < totalPlayers; offset++) {
      final int idx = (discIdx + offset) % totalPlayers;
      if (!state.finishedPlayerIds.contains(newPlayers[idx].id)) {
        clockwiseRemainingIndices.add(idx);
      }
    }

    // --- Edge case: only 0 or 1 active players remain → game over ---
    if (clockwiseRemainingIndices.length <= 1) {
      final List<String> newFinished = List.from(state.finishedPlayerIds);
      if (clockwiseRemainingIndices.isNotEmpty) {
        final winnerId = newPlayers[clockwiseRemainingIndices.first].id;
        if (!newFinished.contains(winnerId)) newFinished.insert(0, winnerId);
      }
      if (!newFinished.contains(disconnectedPlayerId)) {
        newFinished.add(disconnectedPlayerId);
      }
      return MoveResult(
        gameState: state.copyWith(
          players: newPlayers,
          phase: GamePhase.gameOver,
          donkeyPlayerId: disconnectedPlayerId,
          finishedPlayerIds: newFinished,
        ),
        moveType: MoveType.gameCompleted,
      );
    }

    // --- Distribute cards one-by-one clockwise ---
    int recipientCursor = 0;
    for (final card in cardsToDistribute) {
      final int targetIdx =
          clockwiseRemainingIndices[recipientCursor % clockwiseRemainingIndices.length];
      final List<PlayingCard> updatedHand = List.from(newPlayers[targetIdx].hand)..add(card);
      updatedHand.sort((a, b) {
        if (a.suit.index != b.suit.index) return a.suit.index.compareTo(b.suit.index);
        return a.rank.index.compareTo(b.rank.index);
      });
      newPlayers[targetIdx] = newPlayers[targetIdx].copyWith(hand: updatedHand);
      recipientCursor++;
    }

    // --- Determine who plays next based on round state ---
    int nextActiveIdx;
    RoundModel? updatedRound = state.currentRound;

    if (updatedRound == null) {
      // Between rounds — first clockwise player leads
      nextActiveIdx = clockwiseRemainingIndices.first;
    } else {
      // Cards already played on the table MUST REMAIN on the table!
      final Set<String> playedPlayerIds =
          updatedRound.playedCards.map((pc) => pc.playerId).toSet();
      final Set<String> remainingActiveIds =
          clockwiseRemainingIndices.map((i) => newPlayers[i].id).toSet();

      final bool allRemainingPlayed =
          remainingActiveIds.every((id) => playedPlayerIds.contains(id));

      if (allRemainingPlayed && updatedRound.playedCards.isNotEmpty) {
        final highestCard = _moveRules.currentHighestCard(updatedRound.playedCards);
        if (highestCard != null && highestCard.playerId == disconnectedPlayerId) {
          // If the disconnected player had the highest card, clockwise next player leads the next round
          final nextLeaderId = newPlayers[clockwiseRemainingIndices.first].id;
          updatedRound = updatedRound.copyWith(winnerId: nextLeaderId);
        } else if (highestCard != null) {
          updatedRound = updatedRound.copyWith(winnerId: highestCard.playerId);
        }

        final tempState = state.copyWith(
          players: newPlayers,
          currentRound: updatedRound,
        );
        return _completeRound(tempState);
      } else {
        // Continue round on the table — find next clockwise player who hasn't played yet
        nextActiveIdx = clockwiseRemainingIndices.first;
        for (final idx in clockwiseRemainingIndices) {
          if (!playedPlayerIds.contains(newPlayers[idx].id)) {
            nextActiveIdx = idx;
            break;
          }
        }
      }
    }

    final newHistory = state.history.record(
      'system',
      'Player ${disconnectedPlayer.name} left. Cards distributed clockwise to remaining players.',
    );

    return MoveResult(
      gameState: state.copyWith(
        players: newPlayers,
        activePlayerIndex: nextActiveIdx,
        currentRound: updatedRound,
        history: newHistory,
        phase: GamePhase.playerTurn,
      ),
      moveType: MoveType.cardPlayed,
    );
  }

}

