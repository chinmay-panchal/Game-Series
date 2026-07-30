import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../engine/game_engine.dart';
import '../../engine/game_state.dart' as engine;
import '../../engine/move_result.dart';
import '../../engine/rules/move_rules.dart';
import '../../engine/rules/punishment_rules.dart';
import '../../engine/rules/loser_rules.dart';
import '../../models/card_model.dart';
import '../../models/online_room_model.dart';
import '../../models/round_model.dart';
import '../../models/player_model.dart' as pm;
import '../../models/enums/suit.dart';
import '../../models/enums/rank.dart';
import '../../models/enums/game_phase.dart';
import '../../models/played_card.dart';
import '../../services/room_repository.dart';
import '../../services/audio_service.dart';
import 'online_event.dart';
import 'online_state.dart';

class OnlineBloc extends Bloc<OnlineEvent, OnlineState> {
  final RoomRepository repository;
  final GameEngine _engine = GameEngine();
  final MoveRules _moveRules = MoveRules();
  final PunishmentRules _punishmentRules = PunishmentRules();
  final LoserRules _loserRules = LoserRules();
  final AudioService _audio = AudioService();

  // Local runtime state
  OnlineRoomModel? _room;
  String? _myUid;
  String? _myName;
  bool _isHost = false;
  List<OnlinePlayerModel> _players = [];

  // Public getters for guest move submission
  String? get currentRoomId => _room?.roomId;
  String? get myUid => _myUid;

  // Host-only: the running GameState
  engine.GameState? _hostGameState;

  // Guest-only: my hand from RTDB
  List<PlayingCard> _myHand = [];
  Map<Object?, Object?>? _lastReceivedGameState;

  // Subscriptions
  StreamSubscription? _playersSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _gameStateSub;
  StreamSubscription? _pendingActionSub;
  StreamSubscription? _myHandSub;

  OnlineBloc({required this.repository}) : super(OnlineInitial()) {
    on<CreateRoom>(_onCreateRoom);
    on<JoinRoom>(_onJoinRoom);
    on<RejoinExistingRoom>(_onRejoinExistingRoom);
    on<HostStartGame>(_onHostStartGame);
    on<OnlinePlayCard>(_onPlayCard);
    on<OnlineGivePunishment>(_onGivePunishment);
    on<OnlineStartNextRound>(_onStartNextRound);
    on<OnlineDistributeNewCards>(_onDistributeNewCards);
    on<OnlineLeaveRoom>(_onLeaveRoom);
    on<OnlineRestartRoom>(_onRestartRoom);
    on<RemoteGameStateUpdated>(_onRemoteGameStateUpdated);
    on<PendingActionReceived>(_onPendingActionReceived);
    on<PlayersUpdated>(_onPlayersUpdated);
    on<RoomStatusChanged>(_onRoomStatusChanged);
    on<MyHandUpdated>(_onMyHandUpdated);
    on<DisconnectDataUpdated>(_onDisconnectDataUpdated);
  }

  StreamSubscription? _disconnectSub;

  Future<void> _saveSession(String roomId, String roomCode, String name, String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_online_room_id', roomId);
      await prefs.setString('active_online_room_code', roomCode);
      await prefs.setString('active_online_player_name', name);
      await prefs.setString('active_online_player_uid', uid);
    } catch (_) {}
  }

  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_online_room_id');
      await prefs.remove('active_online_room_code');
      await prefs.remove('active_online_player_name');
      await prefs.remove('active_online_player_uid');
    } catch (_) {}
  }

  // ─── Room Creation / Joining ────────────────────────────────────────────────

  Future<void> _onCreateRoom(CreateRoom event, Emitter<OnlineState> emit) async {
    emit(const OnlineLoading('Creating room...'));
    try {
      final room = await repository.createRoom(
        hostName: event.hostName,
        maxPlayers: event.maxPlayers,
      );
      _room = room;
      _myUid = repository.currentUid!;
      _myName = event.hostName;
      _isHost = true;
      await _saveSession(room.roomId, room.roomCode, event.hostName, _myUid!);
      _subscribeToLobby(room.roomId);
      emit(OnlineWaiting(room: room, players: [], isHost: true));
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  Future<void> _onJoinRoom(JoinRoom event, Emitter<OnlineState> emit) async {
    emit(const OnlineLoading('Joining room...'));
    try {
      final room = await repository.joinRoom(
        roomCode: event.roomCode,
        playerName: event.playerName,
      );
      _room = room;
      _myUid = repository.currentUid!;
      _myName = event.playerName;
      _isHost = false;
      await _saveSession(room.roomId, room.roomCode, event.playerName, _myUid!);
      _subscribeToLobby(room.roomId);
      emit(OnlineWaiting(room: room, players: [], isHost: false));
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  Future<void> _onRejoinExistingRoom(RejoinExistingRoom event, Emitter<OnlineState> emit) async {
    emit(const OnlineLoading('Rejoining room...'));
    try {
      final room = await repository.getActiveRoom(event.roomId);
      if (room == null) {
        await _clearSession();
        emit(const OnlineError('Room is no longer active.'));
        return;
      }
      _room = room;
      _myUid = repository.currentUid ?? await repository.signInAnonymously();
      _myName = event.playerName;
      _isHost = (_room!.hostId == _myUid);
      
      await repository.rejoinRoom(event.roomId, _myUid!);
      await _saveSession(room.roomId, room.roomCode, event.playerName, _myUid!);

      _subscribeToLobby(room.roomId);
      _subscribeToGame(room.roomId);

      // Fetch stored game state & my hand immediately from RTDB
      final gameStateData = await repository.getGameState(room.roomId);
      _myHand = await repository.getMyHand(room.roomId, _myUid!);

      if (gameStateData != null) {
        if (_isHost) {
          // Reconstruct _hostGameState on host side
          final playerOrder = (gameStateData['playerOrder'] as List<Object?>? ?? [])
              .map((e) => e.toString())
              .toList();
          final activeIdx = gameStateData['activePlayerIndex'] as int? ?? 0;
          final phaseName = gameStateData['phase'] as String? ?? 'playerTurn';
          final phase = GamePhase.values.firstWhere(
            (p) => p.name == phaseName,
            orElse: () => GamePhase.playerTurn,
          );

          List<pm.Player> enginePlayers = [];
          for (int i = 0; i < playerOrder.length; i++) {
            final uid = playerOrder[i];
            final pHand = await repository.getMyHand(room.roomId, uid);
            final pName = _players.firstWhere((p) => p.uid == uid, orElse: () => OnlinePlayerModel(uid: uid, name: 'Player ${i + 1}', isOnline: true, joinedAt: 0)).name;
            enginePlayers.add(pm.Player(id: 'p$i', name: pName, hand: pHand));
          }

          if (enginePlayers.isNotEmpty) {
            // Parse currentRound
            RoundModel? currentRound;
            final roundData = gameStateData['currentRound'];
            if (roundData is Map<Object?, Object?>) {
              currentRound = _parseRound(roundData);
            }

            // Parse completedRounds
            List<RoundModel> completedRounds = [];
            final completedData = gameStateData['completedRounds'];
            if (completedData is List<Object?>) {
              for (final r in completedData) {
                if (r is Map<Object?, Object?>) {
                  completedRounds.add(_parseRound(r));
                }
              }
            }
            
            // Parse donkey and finished players
            final donkeyUid = gameStateData['donkeyPlayerUid'] as String?;
            final donkeyId = donkeyUid != null && playerOrder.contains(donkeyUid) 
                ? 'p${playerOrder.indexOf(donkeyUid)}' : null;

            final finishedUidsRaw = gameStateData['finishedPlayerUids'] as List<Object?>? ?? [];
            final finishedPlayerIds = finishedUidsRaw.map((uid) {
              final strUid = uid.toString();
              final idx = playerOrder.indexOf(strUid);
              return idx >= 0 ? 'p$idx' : strUid;
            }).toList();

            _hostGameState = engine.GameState(
              players: enginePlayers,
              activePlayerIndex: activeIdx,
              phase: phase,
              currentRound: currentRound,
              completedRounds: completedRounds,
              donkeyPlayerId: donkeyId,
              finishedPlayerIds: finishedPlayerIds,
              unendingLoopDetected: gameStateData['unendingLoopDetected'] as bool? ?? false,
            );
            _emitHostGameState(emit);
            return;
          }
        } else {
          _emitGuestGameState(emit, gameStateData);
          return;
        }
      }

      emit(OnlineWaiting(room: _room!, players: _players, isHost: _isHost));
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  // ─── Lobby Subscriptions ───────────────────────────────────────────────────

  void _subscribeToLobby(String roomId) {
    _playersSub?.cancel();
    _statusSub?.cancel();
    _disconnectSub?.cancel();

    _playersSub = repository.playersStream(roomId).listen((players) {
      add(PlayersUpdated(players));
    });
    _statusSub = repository.roomStatusStream(roomId).listen((status) {
      add(RoomStatusChanged(status));
    });
    _disconnectSub = repository.disconnectDataStream(roomId).listen((data) {
      add(DisconnectDataUpdated(data));
    });
  }

  void _subscribeToGame(String roomId) {
    _gameStateSub?.cancel();

    if (_isHost) {
      // Host listens to pendingAction from guests
      _pendingActionSub?.cancel();
      _pendingActionSub = repository.pendingActionStream(roomId).listen((data) {
        if (data != null) add(PendingActionReceived(data));
      });
    } else {
      // Guest listens to gameState and their own hand
      _gameStateSub = repository.gameStateStream(roomId).listen((data) {
        if (data != null) add(RemoteGameStateUpdated(data));
      });
      _myHandSub?.cancel();
      _myHandSub = repository.myHandStream(roomId, _myUid!).listen((cards) {
        _myHand = cards;
        add(MyHandUpdated(cards));
      });
    }
  }

  // ─── Host: Start Game ──────────────────────────────────────────────────────

  Future<void> _onHostStartGame(HostStartGame event, Emitter<OnlineState> emit) async {
    if (!_isHost || _room == null) return;
    emit(const OnlineLoading('Starting game...'));

    try {
      // Build player names list in join order
      final playerNames = _players.map((p) => p.name).toList();
      final playerUids = _players.map((p) => p.uid).toList();

      // Run engine to create initial game state
      final result = _engine.startGame(playerNames);
      _hostGameState = result.gameState.copyWith(phase: GamePhase.playerTurn);

      // Build serializable gameState (no hands — those go in /hands/)
      final gsMap = _buildPublicGameState(_hostGameState!, playerUids);

      // Build hands per player uid
      final handsPerPlayer = <String, List<Map<String, dynamic>>>{};
      for (int i = 0; i < _hostGameState!.players.length; i++) {
        final uid = playerUids[i];
        handsPerPlayer[uid] = _hostGameState!.players[i].hand
            .map((c) => c.toJson())
            .toList();
      }

      await repository.startGame(
        roomId: _room!.roomId,
        gameState: gsMap,
        handsPerPlayer: handsPerPlayer,
      );

      _subscribeToGame(_room!.roomId);
      _emitHostGameState(emit);
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  void _advanceIfTurnTransition() {
    if (_hostGameState != null && _hostGameState!.phase == GamePhase.turnTransition) {
      _hostGameState = _engine.continueAfterTransition(_hostGameState!).gameState;
    }
  }

  // ─── Host: Play Card ───────────────────────────────────────────────────────

  Future<void> _onPlayCard(OnlinePlayCard event, Emitter<OnlineState> emit) async {
    if (!_isHost || _hostGameState == null) return;
    final myEnginePlayer = _hostGameState!.players[_hostGameState!.activePlayerIndex];
    final result = _engine.playCard(_hostGameState!, myEnginePlayer.id, event.card);
    if (result.moveType == MoveType.invalidMove) {
      _audio.playErrorSound();
      emit(OnlineError(result.message ?? 'Invalid move'));
      _emitHostGameState(emit);
      return;
    }
    _audio.playCardSound();
    _hostGameState = result.gameState;
    _advanceIfTurnTransition();
    await _syncStateToRtdb();
    _emitHostGameState(emit);
  }

  Future<void> _onGivePunishment(OnlineGivePunishment event, Emitter<OnlineState> emit) async {
    if (!_isHost || _hostGameState == null) return;
    final myEnginePlayer = _hostGameState!.players[_hostGameState!.activePlayerIndex];
    final result = _engine.givePunishment(_hostGameState!, myEnginePlayer.id, event.card);
    if (result.moveType == MoveType.invalidMove) {
      _audio.playErrorSound();
      emit(OnlineError(result.message ?? 'Invalid move'));
      _emitHostGameState(emit);
      return;
    }
    _audio.playPunishSound();
    _hostGameState = result.gameState;
    _advanceIfTurnTransition();
    await _syncStateToRtdb();
    _emitHostGameState(emit);
  }

  Future<void> _onStartNextRound(OnlineStartNextRound event, Emitter<OnlineState> emit) async {
    if (!_isHost || _hostGameState == null) return;
    final result = _engine.continueAfterTransition(_hostGameState!);
    _hostGameState = result.gameState;
    _audio.playTurnSwitchSound();
    await _syncStateToRtdb();
    _emitHostGameState(emit);
  }

  Future<void> _onDistributeNewCards(OnlineDistributeNewCards event, Emitter<OnlineState> emit) async {
    if (!_isHost || _hostGameState == null) return;
    final result = _engine.distributeNewCards(_hostGameState!);
    if (result.moveType != MoveType.invalidMove) {
      _hostGameState = result.gameState;
      _audio.playTurnSwitchSound();
      await _syncStateToRtdb();
      _emitHostGameState(emit);
    } else {
      emit(OnlineError(result.message ?? "Cannot distribute cards"));
      _emitHostGameState(emit);
    }
  }

  // ─── Guest: Remote State Updates ──────────────────────────────────────────

  Future<void> _onRemoteGameStateUpdated(
      RemoteGameStateUpdated event, Emitter<OnlineState> emit) async {
    _lastReceivedGameState = event.data;
    _emitGuestGameState(emit, event.data);
  }

  Future<void> _onMyHandUpdated(MyHandUpdated event, Emitter<OnlineState> emit) async {
    // Re-emit state when Guest receives their hand from RTDB
    // This fixes the bug where guest gets 'PlayerTurn' BEFORE their hand stream arrives
    if (!_isHost && _lastReceivedGameState != null) {
      if (state is OnlineWaitingForTurn || state is OnlinePlayerTurn) {
        _emitGuestGameState(emit, _lastReceivedGameState!);
      }
    }
  }

  // ─── Host: Process Guest's Pending Action ─────────────────────────────────

  Future<void> _onPendingActionReceived(
      PendingActionReceived event, Emitter<OnlineState> emit) async {
    if (!_isHost || _hostGameState == null) return;

    final data = event.data;
    final type = data['type'] as String?;
    final suitStr = data['cardSuit'] as String?;
    final rankStr = data['cardRank'] as String?;
    if (suitStr == null || rankStr == null) return;

    final suit = Suit.values.firstWhere((s) => s.name == suitStr,
        orElse: () => Suit.spades);
    final rank = Rank.values.firstWhere((r) => r.name == rankStr,
        orElse: () => Rank.ace);
    final card = PlayingCard(suit: suit, rank: rank);

    final activeId = _hostGameState!.players[_hostGameState!.activePlayerIndex].id;

    MoveResult result;
    if (type == 'givePunishment') {
      result = _engine.givePunishment(_hostGameState!, activeId, card);
      _audio.playPunishSound();
    } else {
      result = _engine.playCard(_hostGameState!, activeId, card);
      _audio.playCardSound();
    }

    if (result.moveType != MoveType.invalidMove) {
      _hostGameState = result.gameState;
      _advanceIfTurnTransition();
      await repository.clearPendingAction(_room!.roomId);
      await _syncStateToRtdb();
    } else {
      // Clear the bad action so guest can try again
      await repository.clearPendingAction(_room!.roomId);
    }
    _emitHostGameState(emit);
  }

  // ─── Players / Status updates ─────────────────────────────────────────────

  void _onPlayersUpdated(PlayersUpdated event, Emitter<OnlineState> emit) {
    _players = event.players;

    // Handle host migration: if current host is offline, elect next
    if (_room != null) {
      final hostPlayer = _players.firstWhere(
        (p) => p.uid == _room!.hostId,
        orElse: () => OnlinePlayerModel(
            uid: '', name: '', isOnline: false, joinedAt: 0),
      );
      if (!hostPlayer.isOnline && _players.isNotEmpty) {
        final onlinePlayers = _players.where((p) => p.isOnline).toList();
        if (onlinePlayers.isNotEmpty) {
          final newHost = onlinePlayers.first;
          if (newHost.uid == _myUid) {
            // I'm the new host
            _isHost = true;
            repository.claimHost(_room!.roomId, _myUid!);
            _room = OnlineRoomModel(
              roomId: _room!.roomId,
              roomCode: _room!.roomCode,
              hostId: _myUid!,
              status: _room!.status,
              maxPlayers: _room!.maxPlayers,
              createdAt: _room!.createdAt,
            );
          }
        }
      }
    }

    // Handle disconnected player during game: set disconnect timer in RTDB
    if (_room != null) {
      final offlinePlayers = _players.where((p) => !p.isOnline).toList();
      if (offlinePlayers.isNotEmpty) {
        for (final p in offlinePlayers) {
          repository.setDisconnectTimer(_room!.roomId, p.uid, p.name);
        }
      } else {
        repository.clearDisconnectData(_room!.roomId);
      }
    }

    if (state is OnlineWaiting) {
      emit(OnlineWaiting(
          room: _room!,
          players: _players,
          isHost: _isHost));
    }
  }

  Timer? _autoWinCheckTimer;

  void _onDisconnectDataUpdated(DisconnectDataUpdated event, Emitter<OnlineState> emit) {
    _autoWinCheckTimer?.cancel();
    final data = event.data;
    if (data == null || _room == null) return;

    final expiresAt = data['expiresAt'] as int? ?? 0;
    final disconnectedUid = data['disconnectedUid'] as String? ?? '';
    final disconnectedName = data['disconnectedName'] as String? ?? 'Player';

    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = expiresAt - now;

    if (remainingMs <= 0) {
      _triggerAutoWin(disconnectedUid, disconnectedName, emit);
    } else {
      // Schedule timer check when 30 seconds timer expires
      _autoWinCheckTimer = Timer(Duration(milliseconds: remainingMs), () {
        add(DisconnectDataUpdated(data));
      });
    }
  }

  Future<void> _onRestartRoom(OnlineRestartRoom event, Emitter<OnlineState> emit) async {
    if (_room == null) return;
    try {
      emit(const OnlineLoading('Restarting game...'));
      await repository.restartRoom(_room!.roomId);
      _hostGameState = null;
      _lastReceivedGameState = null;
      emit(OnlineWaiting(room: _room!, players: _players, isHost: _isHost));
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  void _triggerAutoWin(String disconnectedUid, String disconnectedName, Emitter<OnlineState> emit) {
    if (_room == null) return;
    final remainingPlayers = _players.where((p) => p.uid != disconnectedUid && p.isOnline).toList();

    if (remainingPlayers.isEmpty) {
      // Nobody is left in room — delete room completely from Firebase
      repository.deleteRoom(_room!.roomId, _room!.roomCode);
      _clearSession();
      emit(OnlineInitial());
      return;
    }

    final winnerName = remainingPlayers.first.name;

    repository.completeRoom(_room!.roomId);
    _clearSession();

    emit(OnlineGameFinished(
      donkeyName: '$disconnectedName (Left/Timed out)',
      finishingOrder: [winnerName, '$disconnectedName (Donkey)'],
    ));
  }

  void _onRoomStatusChanged(RoomStatusChanged event, Emitter<OnlineState> emit) {
    if (event.status == 'in_progress' && !_isHost) {
      // Game started — subscribe to game streams as guest
      _subscribeToGame(_room!.roomId);
    }
    if (event.status == 'completed') {
      // Already handled through game state
    }
  }

  // ─── Sync / Emit Helpers ───────────────────────────────────────────────────

  Future<void> _syncStateToRtdb() async {
    if (!_isHost || _hostGameState == null || _room == null) return;
    final playerUids = _players.map((p) => p.uid).toList();
    final gsMap = _buildPublicGameState(_hostGameState!, playerUids);
    final handsPerPlayer = <String, List<Map<String, dynamic>>>{};
    for (int i = 0; i < _hostGameState!.players.length && i < playerUids.length; i++) {
      handsPerPlayer[playerUids[i]] = _hostGameState!.players[i].hand
          .map((c) => c.toJson())
          .toList();
    }
    await repository.writeGameState(
      roomId: _room!.roomId,
      gameState: gsMap,
      handsPerPlayer: handsPerPlayer,
    );
  }

  void _emitHostGameState(Emitter<OnlineState> emit) {
    if (_hostGameState == null) return;
    final gs = _hostGameState!;
    final activeIdx = gs.activePlayerIndex;
    final activeEnginePlayer = gs.players[activeIdx];
    final playerUids = _players.map((p) => p.uid).toList();

    // Find my uid's position — host is always index 0 in _players  
    final myIdx = playerUids.indexOf(_myUid!);
    final myEnginePlayer = myIdx >= 0 && myIdx < gs.players.length
        ? gs.players[myIdx]
        : gs.players[0];

    final isMyTurn = activeEnginePlayer.id == myEnginePlayer.id;

    switch (gs.phase) {
      case GamePhase.playerTurn:
      case GamePhase.turnTransition:
        emit(OnlinePlayerTurn(
          myName: _myName ?? '',
          activePlayerName: activeEnginePlayer.name,
          isMyTurn: isMyTurn,
          myHand: myEnginePlayer.hand,
          currentRound: gs.currentRound,
          currentSuit: gs.currentRound?.suit,
          highestCard: gs.currentRound != null
              ? _moveRules.currentHighestCard(gs.currentRound!.playedCards)
              : null,
          allPlayers: _players,
          isHost: true,
          isFirstTurn: gs.completedRounds.isEmpty && gs.currentRound == null,
          unendingLoopDetected: gs.unendingLoopDetected,
        ));
        break;
      case GamePhase.punishmentSelection:
        final targetId = _punishmentRules.targetOfPunishment(gs.currentRound!.playedCards);
        final targetName = gs.players.firstWhere((p) => p.id == targetId).name;
        if (isMyTurn) {
          emit(OnlinePunishmentNeeded(
            myHand: myEnginePlayer.hand,
            receivingPlayerName: targetName,
          ));
        }
        break;
      case GamePhase.roundEnd:
        final completedRound = gs.completedRounds.last;
        final leaderId = _moveRules.roundLeaderId(completedRound);
        final leaderName = gs.players.firstWhere((p) => p.id == leaderId).name;
        // If punishment card exists, find who received it
        String? punishReceiverName;
        String? punishReceiverUid;
        if (completedRound.punishmentCard != null && completedRound.winnerId != null) {
          final targetId = _punishmentRules.targetOfPunishment(completedRound.playedCards);
          final targetEngineIdx = int.tryParse(targetId.replaceAll('p', ''));
          if (targetEngineIdx != null && targetEngineIdx < playerUids.length) {
            punishReceiverUid = playerUids[targetEngineIdx];
            punishReceiverName = gs.players.firstWhere((p) => p.id == targetId).name;
            // Play sound if host is the one receiving punishment
            if (punishReceiverUid == _myUid) {
              _audio.playPunishSound();
            }
          }
        }
        emit(OnlineRoundCompleted(
          nextRoundLeaderName: leaderName,
          completedRound: completedRound,
          isHost: true,
          punishmentCard: completedRound.punishmentCard,
          punishmentReceiverName: punishReceiverName,
          punishmentReceiverUid: punishReceiverUid,
        ));
        break;
      case GamePhase.gameOver:
        final donkeyId = gs.donkeyPlayerId!;
        final donkeyName = gs.players.firstWhere((p) => p.id == donkeyId).name;
        final finishing = gs.finishedPlayerIds
            .map((id) => gs.players.firstWhere((p) => p.id == id).name)
            .toList()
          ..add(donkeyName);
        repository.completeRoom(_room!.roomId);
        emit(OnlineGameFinished(donkeyName: donkeyName, finishingOrder: finishing));
        break;
      case GamePhase.dealing:
        break;
    }
  }

  void _emitGuestGameState(Emitter<OnlineState> emit, Map<Object?, Object?> data) {
    final phase = data['phase'] as String? ?? 'playerTurn';
    final activeIdx = data['activePlayerIndex'] as int? ?? 0;
    final playerOrder = (data['playerOrder'] as List<Object?>? ?? [])
        .map((e) => e.toString())
        .toList();

    if (playerOrder.isEmpty) return;

    final activeUid = activeIdx < playerOrder.length ? playerOrder[activeIdx] : '';
    final activePlayer = _players.firstWhere(
      (p) => p.uid == activeUid,
      orElse: () => OnlinePlayerModel(uid: '', name: 'Unknown', isOnline: true, joinedAt: 0),
    );
    final isMyTurn = activeUid == _myUid;

    // Deserialize round
    RoundModel? currentRound;
    final roundData = data['currentRound'];
    if (roundData is Map<Object?, Object?>) {
      currentRound = _parseRound(roundData);
    }

    List<RoundModel> completedRounds = [];
    final completedData = data['completedRounds'];
    if (completedData is List<Object?>) {
      for (final r in completedData) {
        if (r is Map<Object?, Object?>) {
          completedRounds.add(_parseRound(r));
        }
      }
    }

    switch (phase) {
      case 'playerTurn':
      case 'turnTransition':
        if (isMyTurn) {
          emit(OnlinePlayerTurn(
            myName: _myName ?? '',
            activePlayerName: activePlayer.name,
            isMyTurn: true,
            myHand: _myHand,
            currentRound: currentRound,
            currentSuit: currentRound?.suit,
            highestCard: currentRound != null
                ? _moveRules.currentHighestCard(currentRound.playedCards)
                : null,
            allPlayers: _players,
            isHost: false,
            isFirstTurn: completedRounds.isEmpty && currentRound == null,
            unendingLoopDetected: data['unendingLoopDetected'] as bool? ?? false,
          ));
        } else {
          emit(OnlineWaitingForTurn(
            activePlayerName: activePlayer.name,
            myHand: _myHand,
            currentRound: currentRound,
            allPlayers: _players,
          ));
        }
        break;
      case 'punishmentSelection':
        if (isMyTurn) {
          final playedCards = currentRound?.playedCards ?? [];
          final targetId = playedCards.isNotEmpty
              ? _punishmentRules.targetOfPunishment(playedCards)
              : '';
          final targetUid = targetId.isNotEmpty && playerOrder.length > int.tryParse(targetId.replaceAll('p', ''))!
              ? playerOrder[int.parse(targetId.replaceAll('p', ''))]
              : '';
          final targetPlayer = _players.firstWhere(
            (p) => p.uid == targetUid,
            orElse: () => OnlinePlayerModel(uid: '', name: 'Player', isOnline: true, joinedAt: 0),
          );
          emit(OnlinePunishmentNeeded(
            myHand: _myHand,
            receivingPlayerName: targetPlayer.name,
          ));
        } else {
          emit(OnlineWaitingForTurn(
            activePlayerName: activePlayer.name,
            myHand: _myHand,
            currentRound: currentRound,
            allPlayers: _players,
          ));
        }
        break;
      case 'roundEnd':
        final winnerId = data['lastRoundWinnerId'] as String? ?? '';
        final winnerIdx = playerOrder.indexOf(winnerId);
        final winnerName = winnerIdx >= 0 && winnerIdx < _players.length
            ? _players[winnerIdx].name
            : 'Unknown';
        final lastRound = completedRounds.isNotEmpty
            ? completedRounds.last
            : RoundModel(
                roundNumber: 0,
                suit: Suit.spades,
                leadPlayerId: '',
                playedCards: []);
        // Punishment info — read directly from stored round data (no local computation needed)
        String? punishReceiverName;
        String? punishReceiverUid;
        if (lastRound.punishmentCard != null) {
          // Host stored punishmentReceiverUid directly in the completed round map
          final completedRaw = data['completedRounds'];
          if (completedRaw is List<Object?> && completedRaw.isNotEmpty) {
            final lastRaw = completedRaw.last;
            if (lastRaw is Map<Object?, Object?>) {
              punishReceiverUid = lastRaw['punishmentReceiverUid'] as String?;
            }
          }
          if (punishReceiverUid != null) {
            punishReceiverName = _players.firstWhere(
              (p) => p.uid == punishReceiverUid,
              orElse: () => OnlinePlayerModel(uid: '', name: 'Player', isOnline: true, joinedAt: 0),
            ).name;
          }
          // Play punishment sound if I am the one being punished
          if (punishReceiverUid == _myUid) {
            _audio.playPunishSound();
          }
        }
        emit(OnlineRoundCompleted(
          nextRoundLeaderName: winnerName,
          completedRound: lastRound,
          isHost: false,
          punishmentCard: lastRound.punishmentCard,
          punishmentReceiverName: punishReceiverName,
          punishmentReceiverUid: punishReceiverUid,
        ));
        break;
      case 'gameOver':
        final donkeyUid = data['donkeyPlayerUid'] as String? ?? '';
        final donkeyPlayer = _players.firstWhere(
          (p) => p.uid == donkeyUid,
          orElse: () => OnlinePlayerModel(uid: '', name: 'Unknown', isOnline: true, joinedAt: 0),
        );
        final finishedUids = (data['finishedPlayerUids'] as List<Object?>? ?? [])
            .map((e) => e.toString())
            .toList();
        final finishing = finishedUids.map((uid) {
          return _players
              .firstWhere((p) => p.uid == uid,
                  orElse: () => OnlinePlayerModel(
                      uid: uid, name: uid, isOnline: true, joinedAt: 0))
              .name;
        }).toList()
          ..add(donkeyPlayer.name);
        emit(OnlineGameFinished(
            donkeyName: donkeyPlayer.name, finishingOrder: finishing));
        break;
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildPublicGameState(engine.GameState gs, List<String> playerUids) {
    final phase = gs.phase == GamePhase.turnTransition ? 'playerTurn' : gs.phase.name;

    Map<String, dynamic>? roundMap;
    if (gs.currentRound != null) {
      roundMap = _roundToMap(gs.currentRound!, playerUids);
    }

    final completedMaps = gs.completedRounds
        .map((r) => _roundToMap(r, playerUids))
        .toList();

    // Determine winner uid for last round
    String lastRoundWinnerUid = '';
    if (gs.completedRounds.isNotEmpty) {
      final leaderId = _moveRules.roundLeaderId(gs.completedRounds.last);
      final leaderIdx = gs.players.indexWhere((p) => p.id == leaderId);
      if (leaderIdx >= 0 && leaderIdx < playerUids.length) {
        lastRoundWinnerUid = playerUids[leaderIdx];
      }
    }

    String? donkeyUid;
    if (gs.donkeyPlayerId != null) {
      final donkeyIdx = gs.players.indexWhere((p) => p.id == gs.donkeyPlayerId);
      if (donkeyIdx >= 0 && donkeyIdx < playerUids.length) {
        donkeyUid = playerUids[donkeyIdx];
      }
    }

    final finishedUids = gs.finishedPlayerIds.map((id) {
      final idx = gs.players.indexWhere((p) => p.id == id);
      return idx >= 0 && idx < playerUids.length ? playerUids[idx] : id;
    }).toList();

    return {
      'phase': phase,
      'activePlayerIndex': gs.activePlayerIndex,
      'playerOrder': playerUids,
      'currentRound': roundMap,
      'completedRounds': completedMaps,
      'lastRoundWinnerId': lastRoundWinnerUid,
      'donkeyPlayerUid': donkeyUid,
      'finishedPlayerUids': finishedUids,
      'unendingLoopDetected': gs.unendingLoopDetected,
    };
  }

  Map<String, dynamic> _roundToMap(RoundModel r, List<String> playerUids) {
    // Also store punishmentReceiverUid directly so guests can check cheaply
    String? punishmentReceiverUid;
    if (r.punishmentCard != null && r.playedCards.isNotEmpty) {
      final targetId = _punishmentRules.targetOfPunishment(r.playedCards);
      final targetIdx = int.tryParse(targetId.replaceAll('p', ''));
      if (targetIdx != null && targetIdx < playerUids.length) {
        punishmentReceiverUid = playerUids[targetIdx];
      }
    }
    return {
      'roundNumber': r.roundNumber,
      'suit': r.suit.name,
      'leadPlayerId': r.leadPlayerId,
      'winnerId': r.winnerId,
      'playedCards': r.playedCards.map((pc) => {
        'playerId': pc.playerId,
        'card': pc.card.toJson(),
      }).toList(),
      // Punishment fields — only set when punishment occurred
      if (r.punishmentCard != null) 'punishmentCard': r.punishmentCard!.toJson(),
      if (punishmentReceiverUid != null) 'punishmentReceiverUid': punishmentReceiverUid,
    };
  }

  RoundModel _parseRound(Map<Object?, Object?> data) {
    final suitStr = data['suit'] as String? ?? 'spades';
    final suit = Suit.values.firstWhere((s) => s.name == suitStr, orElse: () => Suit.spades);
    final playedCardsRaw = data['playedCards'] as List<Object?>? ?? [];
    final playedCards = playedCardsRaw.whereType<Map<Object?, Object?>>().map((pc) {
      final cardData = pc['card'] as Map<Object?, Object?>? ?? {};
      final m = cardData.map((k, v) => MapEntry(k.toString(), v));
      return PlayedCard(
        playerId: pc['playerId'] as String? ?? '',
        card: PlayingCard.fromJson(m),
      );
    }).toList();
    // Parse optional punishment card
    PlayingCard? punishmentCard;
    final punishCardRaw = data['punishmentCard'];
    if (punishCardRaw is Map<Object?, Object?>) {
      final m = punishCardRaw.map((k, v) => MapEntry(k.toString(), v));
      punishmentCard = PlayingCard.fromJson(m);
    }
    return RoundModel(
      roundNumber: data['roundNumber'] as int? ?? 0,
      suit: suit,
      leadPlayerId: data['leadPlayerId'] as String? ?? '',
      playedCards: playedCards,
      winnerId: data['winnerId'] as String?,
      punishmentCard: punishmentCard,
    );
  }

  Future<void> _onLeaveRoom(OnlineLeaveRoom event, Emitter<OnlineState> emit) async {
    if (_room != null && _myUid != null) {
      await repository.leaveRoom(_room!.roomId, _myUid!);
    }
    await _clearSession();
    _cancelAllSubscriptions();
    _room = null;
    _myUid = null;
    _myName = null;
    _isHost = false;
    _hostGameState = null;
    _players = [];
    emit(OnlineInitial());
  }

  void _cancelAllSubscriptions() {
    _playersSub?.cancel();
    _statusSub?.cancel();
    _gameStateSub?.cancel();
    _pendingActionSub?.cancel();
    _myHandSub?.cancel();
    _disconnectSub?.cancel();
    _autoWinCheckTimer?.cancel();
  }

  @override
  Future<void> close() {
    _cancelAllSubscriptions();
    return super.close();
  }
}
