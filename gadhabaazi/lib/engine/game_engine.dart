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
        hand: [...players[currentPlayerIndex].hand, deck.removeLast()]
      );
      currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    }

    // Sort hands for better UX
    for (int i = 0; i < players.length; i++) {
      List<PlayingCard> sortedHand = List.from(players[i].hand);
      sortedHand.sort((a, b) {
        if (a.suit.index != b.suit.index) return a.suit.index.compareTo(b.suit.index);
        return a.rank.index.compareTo(b.rank.index); // Ascending order
      });
      players[i] = players[i].copyWith(hand: sortedHand);
    }

    // Find the player with Ace of Spades
    int starterIndex = 0;
    for (int i = 0; i < players.length; i++) {
      if (players[i].hand.any((c) => c.suit == Suit.spades && c.rank == Rank.ace)) {
        starterIndex = i;
        break;
      }
    }

    MoveHistory history = const MoveHistory();
    history = history.record('system', 'Game started with ${players.length} players.');
    history = history.record(players[starterIndex].id, 'Has Ace of Spades, starts the game.');

    final initialState = GameState(
      players: players,
      activePlayerIndex: starterIndex,
      phase: GamePhase.dealing,
      history: history,
    );

    return MoveResult(
      gameState: initialState,
      moveType: MoveType.cardPlayed, // Initial state, but let UI transition from dealing to playerTurn
    );
  }

  MoveResult playCard(GameState state, String playerId, PlayingCard card) {
    if (state.players[state.activePlayerIndex].id != playerId) {
      return MoveResult(gameState: state, moveType: MoveType.invalidMove, message: "Not your turn");
    }

    Player activePlayer = state.players[state.activePlayerIndex];
    
    // Check if player actually has the card
    if (!activePlayer.hand.contains(card)) {
      return MoveResult(gameState: state, moveType: MoveType.invalidMove, message: "You don't own this card");
    }

    RoundModel currentRound = state.currentRound ?? RoundModel(
      roundNumber: state.completedRounds.length + 1,
      suit: card.suit,
      leadPlayerId: playerId,
      playedCards: [],
    );

    if (currentRound.playedCards.isNotEmpty) {
      bool canPlay = _moveRules.canPlayCard(activePlayer, card, currentRound.suit);
      if (!canPlay) {
        if (_moveRules.mustPunish(activePlayer, currentRound.suit)) {
          return MoveResult(
            gameState: state.copyWith(phase: GamePhase.punishmentSelection), 
            moveType: MoveType.punishmentRequired,
            message: "You must give a punishment card!"
          );
        }
        return MoveResult(
          gameState: state, 
          moveType: MoveType.invalidMove,
          message: "You must follow the current suit!"
        );
      }
    }

    // Special rule for first round: MUST play Ace of Spades if they have it and it's the first card
    if (state.completedRounds.isEmpty && currentRound.playedCards.isEmpty) {
      if (card.suit != Suit.spades || card.rank != Rank.ace) {
        return MoveResult(
          gameState: state, 
          moveType: MoveType.invalidMove,
          message: "You must start with the Ace of Spades!"
        );
      }
    }

    // Play the card
    List<PlayingCard> newHand = List.from(activePlayer.hand)..remove(card);
    Player updatedPlayer = activePlayer.copyWith(hand: newHand);
    List<Player> newPlayers = List.from(state.players)..[state.activePlayerIndex] = updatedPlayer;

    final playedCard = PlayedCard(playerId: playerId, card: card);
    currentRound = currentRound.copyWith(playedCards: [...currentRound.playedCards, playedCard]);

    MoveHistory newHistory = state.history.record(playerId, "Played ${card.suit.symbol}${card.rank.label}");

    GameState newState = state.copyWith(
      players: newPlayers,
      currentRound: currentRound,
      history: newHistory,
    );

    // Check if round is over
    int activePlayerCount = newPlayers.where((p) => _loserRules.isActive(p)).length;
    if (currentRound.playedCards.length == activePlayerCount || currentRound.playedCards.length == newPlayers.length) {
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
    final newHistory = state.history.record('system', "Round ${state.currentRound!.roundNumber} complete. $roundLeaderId leads next round.");

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
      final finalHistory = newState.history.record('system', 'Game Over. Donkey is $donkeyId');
      
      return MoveResult(
        gameState: newState.copyWith(
          phase: GamePhase.gameOver,
          donkeyPlayerId: donkeyId,
          history: finalHistory,
        ),
        moveType: MoveType.gameCompleted,
      );
    }

    return MoveResult(
      gameState: newState.copyWith(phase: GamePhase.roundEnd),
      moveType: MoveType.roundCompleted,
    );
  }

  MoveResult givePunishment(GameState state, String giverId, PlayingCard card) {
    if (state.players[state.activePlayerIndex].id != giverId) {
      return MoveResult(gameState: state, moveType: MoveType.invalidMove, message: "Not your turn");
    }

    Player giver = state.players[state.activePlayerIndex];
    if (!giver.hand.contains(card)) {
      return MoveResult(gameState: state, moveType: MoveType.invalidMove, message: "You don't own this card");
    }

    // Find who holds the highest card — they receive the punishment card
    String targetId = _punishmentRules.targetOfPunishment(state.currentRound!.playedCards);
    int targetIndex = state.players.indexWhere((p) => p.id == targetId);

    // Start with a mutable copy of all players
    List<Player> newPlayers = List.from(state.players);

    // Step 1: Return all cards played on the table BACK to the players who played them.
    //         This is the core rule: only the punishment card transfers, the played cards go home.
    for (final playedCard in state.currentRound!.playedCards) {
      int playerIdx = newPlayers.indexWhere((p) => p.id == playedCard.playerId);
      if (playerIdx != -1) {
        List<PlayingCard> returnedHand = List.from(newPlayers[playerIdx].hand)..add(playedCard.card);
        newPlayers[playerIdx] = newPlayers[playerIdx].copyWith(hand: returnedHand);
      }
    }

    // Step 2: Remove the punishment card from the giver's hand
    int giverIndex = newPlayers.indexWhere((p) => p.id == giverId);
    List<PlayingCard> newGiverHand = List.from(newPlayers[giverIndex].hand)..remove(card);
    newPlayers[giverIndex] = newPlayers[giverIndex].copyWith(hand: newGiverHand);

    // Step 3: Add the punishment card to the target (highest card holder)
    List<PlayingCard> newTargetHand = List.from(newPlayers[targetIndex].hand)..add(card);
    newPlayers[targetIndex] = newPlayers[targetIndex].copyWith(hand: newTargetHand);

    MoveHistory newHistory = state.history.record(giverId, "Gave punishment card to $targetId. All played cards returned.");

    // The giver of the punishment leads the next round
    GameState newState = state.copyWith(
      players: newPlayers,
      history: newHistory,
      currentRound: state.currentRound!.copyWith(winnerId: giverId),
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
