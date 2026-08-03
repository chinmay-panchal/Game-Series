import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../engine/game_engine.dart';
import '../../engine/game_state.dart' as engine_state;
import '../../engine/move_result.dart';
import '../../models/enums/game_phase.dart';
import '../../engine/rules/move_rules.dart';
import '../../engine/rules/punishment_rules.dart';
import '../../services/audio_service.dart';
import 'game_event.dart';
import 'game_state.dart';

class GameBloc extends Bloc<GameEvent, GameBlocState> {
  final GameEngine _engine;
  engine_state.GameState? _internalState;
  
  final MoveRules _moveRules = MoveRules();
  final PunishmentRules _punishmentRules = PunishmentRules();
  final AudioService _audio = AudioService();

  GameBloc({required GameEngine engine})
      : _engine = engine,
        super(GameInitial()) {
    on<StartGame>(_onStartGame);
    on<LoadGame>(_onLoadGame);
    on<DealingAnimationCompleted>(_onDealingAnimationCompleted);
    on<RevealHand>(_onRevealHand);
    on<PlayCard>(_onPlayCard);
    on<GivePunishmentCard>(_onGivePunishmentCard);
    on<StartNextRound>(_onStartNextRound);
    on<DistributeNewCards>(_onDistributeNewCards);
    on<RestartGame>(_onRestartGame);
  }

  Future<void> _saveState() async {
    if (_internalState == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(_internalState!.toJson());
      await prefs.setString('saved_game', jsonString);
    } catch (e) {
      // Ignored for now
    }
  }

  void _onStartGame(StartGame event, Emitter<GameBlocState> emit) {
    final result = _engine.startGame(event.playerNames);
    _internalState = result.gameState;
    _saveState();
    
    emit(GameDealing(_internalState!.players));
  }

  void _onLoadGame(LoadGame event, Emitter<GameBlocState> emit) {
    try {
      final jsonMap = jsonDecode(event.jsonState) as Map<String, dynamic>;
      _internalState = engine_state.GameState.fromJson(jsonMap);
      _emitStateBasedOnPhase(emit, _internalState!, isHandRevealed: false);
    } catch (e) {
      emit(const GameError("Failed to load game."));
      emit(GameInitial());
    }
  }

  void _onDealingAnimationCompleted(DealingAnimationCompleted event, Emitter<GameBlocState> emit) {
    if (_internalState == null) return;
    
    _internalState = _internalState!.copyWith(phase: GamePhase.playerTurn);
    _saveState();
    
    _emitStateBasedOnPhase(emit, _internalState!, isHandRevealed: false, isFirstTurn: true);
  }

  void _onRevealHand(RevealHand event, Emitter<GameBlocState> emit) {
    if (_internalState == null) return;
    _emitStateBasedOnPhase(emit, _internalState!, isHandRevealed: true);
  }

  void _onPlayCard(PlayCard event, Emitter<GameBlocState> emit) {
    if (_internalState == null) return;

    final playerId = _internalState!.players[_internalState!.activePlayerIndex].id;
    final result = _engine.playCard(_internalState!, playerId, event.card);
    _internalState = result.gameState;
    _saveState();

    if (result.moveType == MoveType.invalidMove) {
      _audio.playErrorSound();
      emit(GameError(result.message ?? "Invalid move"));
      _emitStateBasedOnPhase(emit, _internalState!);
      return;
    }
    
    _audio.playCardSound();
    _emitStateBasedOnPhase(emit, _internalState!);
  }

  void _onGivePunishmentCard(GivePunishmentCard event, Emitter<GameBlocState> emit) {
    if (_internalState == null) return;

    final giverId = _internalState!.players[_internalState!.activePlayerIndex].id;
    final result = _engine.givePunishment(_internalState!, giverId, event.card);
    _internalState = result.gameState;
    _saveState();

    if (result.moveType == MoveType.invalidMove) {
      _audio.playErrorSound();
      emit(GameError(result.message ?? "Invalid move"));
      _emitStateBasedOnPhase(emit, _internalState!);
      return;
    }

    _audio.playPunishSound();
    _emitStateBasedOnPhase(emit, _internalState!);
  }

  void _onStartNextRound(StartNextRound event, Emitter<GameBlocState> emit) {
    if (_internalState == null) return;
    
    final result = _engine.continueAfterTransition(_internalState!);
    _internalState = result.gameState;
    _saveState();
    
    _audio.playTurnSwitchSound();
    _emitStateBasedOnPhase(emit, _internalState!);
  }

  void _onRestartGame(RestartGame event, Emitter<GameBlocState> emit) async {
    _internalState = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_game');
    } catch (e) {
      // Ignore
    }
    emit(GameInitial());
  }

  void _onDistributeNewCards(DistributeNewCards event, Emitter<GameBlocState> emit) {
    if (_internalState == null) return;
    final result = _engine.distributeNewCards(_internalState!);
    if (result.moveType != MoveType.invalidMove) {
      _internalState = result.gameState;
      _saveState();
      _audio.playTurnSwitchSound();
      _emitStateBasedOnPhase(emit, _internalState!);
    } else {
      emit(GameError(result.message ?? "Cannot distribute cards"));
      _emitStateBasedOnPhase(emit, _internalState!);
    }
  }

  void _emitStateBasedOnPhase(Emitter<GameBlocState> emit, engine_state.GameState state, {bool isHandRevealed = false, bool isFirstTurn = false}) {
    switch (state.phase) {
      case GamePhase.dealing:
        emit(GameDealing(state.players));
        break;
      case GamePhase.turnTransition:
        // Turn transition should now immediately go to player turn hidden
        final result = _engine.continueAfterTransition(state);
        _internalState = result.gameState;
        _emitStateBasedOnPhase(emit, _internalState!, isHandRevealed: false);
        break;
      case GamePhase.playerTurn:
        final activePlayer = state.players[state.activePlayerIndex];
        final otherPlayers = state.players.where((p) => p.id != activePlayer.id).toList();
        final Map<String, String> pNames = {for (var p in state.players) p.id: p.name};
        emit(GamePlayerTurn(
          activePlayer: activePlayer,
          otherPlayers: otherPlayers,
          playerNames: pNames,
          currentRound: state.currentRound,
          currentSuit: state.currentRound?.suit,
          highestCard: state.currentRound != null 
              ? _moveRules.currentHighestCard(state.currentRound!.playedCards) 
              : null,
          isHandRevealed: isHandRevealed,
          isFirstTurn: isFirstTurn,
          unendingLoopDetected: state.unendingLoopDetected,
        ));
        break;
      case GamePhase.punishmentSelection:
        final givingPlayer = state.players[state.activePlayerIndex];
        final targetId = _punishmentRules.targetOfPunishment(state.currentRound!.playedCards);
        final receivingPlayer = state.players.firstWhere((p) => p.id == targetId);
        
        emit(GamePunishmentSelection(
          givingPlayer: givingPlayer,
          receivingPlayerName: receivingPlayer.name,
        ));
        break;
      case GamePhase.roundEnd:
        final leaderId = _moveRules.roundLeaderId(state.completedRounds.last);
        final leaderName = state.players.firstWhere((p) => p.id == leaderId).name;
        final Map<String, String> pNames = {for (var p in state.players) p.id: p.name};
        
        emit(GameRoundCompleted(
          nextRoundLeaderName: leaderName,
          completedRound: state.completedRounds.last,
          playerNames: pNames,
        ));
        break;
      case GamePhase.gameOver:
        final donkeyId = state.donkeyPlayerId!;
        final donkeyName = state.players.firstWhere((p) => p.id == donkeyId).name;
        
        // Compute finishing order
        List<String> finishingOrderNames = [];
        for (var id in state.finishedPlayerIds) {
          finishingOrderNames.add(state.players.firstWhere((p) => p.id == id).name);
        }
        // Donkey is last
        finishingOrderNames.add(donkeyName);

        emit(GameFinished(
          donkeyName: donkeyName,
          finishingOrder: finishingOrderNames,
          history: state.history,
        ));
        break;
    }
  }
}
