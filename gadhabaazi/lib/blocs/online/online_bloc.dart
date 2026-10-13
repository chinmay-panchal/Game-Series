import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../engine/game_engine.dart';
import '../../engine/game_state.dart' as engine;
import '../../engine/move_result.dart';
import '../../engine/rules/move_rules.dart';
import '../../engine/rules/punishment_rules.dart';
import '../../models/card_model.dart';
import '../../models/player_model.dart';
import '../../models/online_room_model.dart';
import '../../models/round_model.dart';
import '../../models/enums/suit.dart';
import '../../models/enums/rank.dart';
import '../../models/enums/game_phase.dart';
import '../../models/played_card.dart';
import '../../engine/history/move_history.dart';
import '../../services/room_repository.dart';
import '../../services/audio_service.dart';
import 'online_event.dart';
import 'online_state.dart';

class OnlineBloc extends Bloc<OnlineEvent, OnlineState> {
  final RoomRepository repository;
  final GameEngine _engine = GameEngine();
  final MoveRules _moveRules = MoveRules();
  final PunishmentRules _punishmentRules = PunishmentRules();
  final AudioService _audio = AudioService();

  // Local runtime state
  OnlineRoomModel? _room;
  String? _myUid;
  String? _myName;
  bool _isHost = false;
  List<OnlinePlayerModel> _players = [];
  List<OnlinePlayerModel> _gamePlayers = [];

  // Public getters
  String? get currentRoomId => _room?.roomId;
  String? get currentRoomCode => _room?.roomCode;
  String? get myUid => _myUid;
  String? get myName => _myName;

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
  StreamSubscription? _connectionSub;
  StreamSubscription? _wonPlayersSub;
  Timer? _heartbeatTimer;
  // Track which player UIDs we have already redistributed (prevent duplicate redistribution)
  final Set<String> _redistributedUids = {};
  bool _hasLeft = false;

  // Finished / Won players tracking
  List<String> _finishedPlayerUids = [];
  final Set<String> _wonPlayerUids = {};

  String? get roomId => _room?.roomId;

  bool isPlayerWon(String uid) {
    if (_wonPlayerUids.contains(uid)) return true;
    if (_finishedPlayerUids.contains(uid)) return true;
    final p = _players.where((p) => p.uid == uid).firstOrNull;
    if (p != null && p.hasWon) return true;
    final gp = _gamePlayers.where((gp) => gp.uid == uid).firstOrNull;
    if (gp != null && gp.hasWon) return true;
    if (_isHost && _hostGameState != null) {
      final myIdx = _gamePlayers.indexWhere((p) => p.uid == uid);
      if (myIdx >= 0 && myIdx < _hostGameState!.players.length) {
        if (_hostGameState!.players[myIdx].hand.isEmpty) return true;
        if (_hostGameState!.finishedPlayerIds.contains(_hostGameState!.players[myIdx].id)) return true;
      }
    }
    if (uid == _myUid && _isGameActive && _myHand.isEmpty && _gamePlayers.isNotEmpty) {
      return true;
    }
    return false;
  }

  bool get isCurrentPlayerWon => _myUid != null && isPlayerWon(_myUid!);
  bool get _hasWon => isCurrentPlayerWon;

  // Presence & activity tracking: Rely on Firebase RTDB onDisconnect
  // to avoid false disconnects when user is on a phone call or minimized.
  final Map<String, int> _playerLastHeardLocal = {};
  final Map<String, int> _playerLastSeenRemote = {};

  bool _isPlayerActive(OnlinePlayerModel p) {
    if (p.uid == _myUid) return true;
    return p.isOnline;
  }

  bool get _isGameActive =>
      _room?.status == 'in_progress' ||
      state is OnlinePlayerTurn ||
      state is OnlineWaitingForTurn ||
      state is OnlineRoundCompleted ||
      state is OnlinePunishmentNeeded ||
      state is OnlineRedistributingCards ||
      _hostGameState != null;

  OnlineBloc({required this.repository}) : super(OnlineInitial()) {
    on<CreateRoom>(_onCreateRoom);
    on<JoinRoom>(_onJoinRoom);
    on<HostStartGame>(_onHostStartGame);
    on<OnlinePlayCard>(_onPlayCard);
    on<OnlineGivePunishment>(_onGivePunishment);
    on<OnlineStartNextRound>(_onStartNextRound);
    on<OnlineDistributeNewCards>(_onDistributeNewCards);
    on<OnlineLeaveRoom>(_onLeaveRoom);
    on<OnlineRestartRoom>(_onRestartRoom);
    on<OnlineReassertPresence>(_onReassertPresence);
    on<RemoteGameStateUpdated>(_onRemoteGameStateUpdated);
    on<PendingActionReceived>(_onPendingActionReceived);
    on<PlayersUpdated>(_onPlayersUpdated);
    on<RoomStatusChanged>(_onRoomStatusChanged);
    on<RoomMetaChanged>(_onRoomMetaChanged);
    on<MyHandUpdated>(_onMyHandUpdated);
    on<OnlinePlayerLeft>(_onPlayerLeft);
  }

  Future<void> _saveSession(
    String roomId,
    String roomCode,
    String name,
    String uid,
  ) async {
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
      await prefs.remove('active_game_in_progress');
      await prefs.remove('active_player_has_won');
    } catch (_) {}
  }

  // ─── Room Creation / Joining ────────────────────────────────────────────────

  Future<void> _onCreateRoom(
    CreateRoom event,
    Emitter<OnlineState> emit,
  ) async {
    _hasLeft = false;
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
    _hasLeft = false;
    emit(const OnlineLoading('Joining room...'));
    try {
      final room = await repository.joinRoom(
        roomCode: event.roomCode,
        playerName: event.playerName,
      );
      _room = room;
      _myUid = repository.currentUid!;
      _myName = event.playerName;
      _isHost = (_room!.hostId == _myUid);
      await _saveSession(room.roomId, room.roomCode, event.playerName, _myUid!);
      _subscribeToLobby(room.roomId);
      emit(OnlineWaiting(room: room, players: [], isHost: _isHost));
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    // Send heartbeat every 2 seconds to RTDB to indicate active presence
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 2000), (_) {
      if (_room != null && _myUid != null) {
        repository.updatePlayerPresence(_room!.roomId, _myUid!);
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  // ─── Lobby Subscriptions ───────────────────────────────────────────────────

  void _subscribeToLobby(String roomId) {
    _playersSub?.cancel();
    _statusSub?.cancel();
    _connectionSub?.cancel();

    _startHeartbeat();

    _playersSub = repository.playersStream(roomId).listen((players) {
      add(PlayersUpdated(players));
    });
    _statusSub = repository.roomMetaStream(roomId).listen((meta) {
      if (meta != null) add(RoomMetaChanged(meta));
    });
    _connectionSub = repository.onConnectionChanged.listen((connected) {
      if (connected && _room != null && _myUid != null) {
        add(OnlineReassertPresence());
      }
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
      // Host ALSO listens to gameStateStream specifically for gameOver/forfeit events!
      _gameStateSub?.cancel();
      _gameStateSub = repository.gameStateStream(roomId).listen((data) {
        if (data != null && data['phase'] == 'gameOver') {
          add(RemoteGameStateUpdated(data));
        }
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

    _wonPlayersSub?.cancel();
    _wonPlayersSub = repository.wonPlayerUidsStream(roomId).listen((uids) {
      _wonPlayerUids.addAll(uids);
      for (final uid in uids) {
        if (!_finishedPlayerUids.contains(uid)) {
          _finishedPlayerUids.add(uid);
        }
      }
    });
  }

  Future<void> _onReassertPresence(
    OnlineReassertPresence event,
    Emitter<OnlineState> emit,
  ) async {
    if (_room == null || _myUid == null) return;
    try {
      await repository.rejoinRoom(_room!.roomId, _myUid!, _myName);
      if (_room!.hostId == _myUid && _room!.status == 'waiting') {
        _isHost = true;
      }
    } catch (e) {
      debugPrint('Failed to reassert presence: $e');
    }
  }

  // ─── Host: Start Game ──────────────────────────────────────────────────────

  Future<void> _onHostStartGame(
    HostStartGame event,
    Emitter<OnlineState> emit,
  ) async {
    // Only the host can start the game!
    if (!_isHost || _room == null) return;
    final activeOnlinePlayers = _players.where((p) => p.isOnline).toList();
    if (activeOnlinePlayers.length < 2) {
      emit(const OnlineError('Need at least 2 players to start.'));
      return;
    }
    emit(const OnlineLoading('Starting game...'));

    try {
      final playerNames = activeOnlinePlayers.map((p) => p.name).toList();
      final playerUids = activeOnlinePlayers.map((p) => p.uid).toList();
      _gamePlayers = List.from(activeOnlinePlayers);

      final result = _engine.startGame(playerNames);
      _hostGameState = result.gameState.copyWith(phase: GamePhase.playerTurn);

      final gsMap = _buildPublicGameState(_hostGameState!, playerUids);

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

      _room = _room!.copyWith(status: 'in_progress');
      _redistributedUids.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_game_in_progress', 'true');
      await prefs.remove('active_player_has_won');
      _subscribeToGame(_room!.roomId);
      _emitHostGameState(emit);
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  void _advanceIfTurnTransition() {
    if (_hostGameState != null &&
        _hostGameState!.phase == GamePhase.turnTransition) {
      _hostGameState = _engine
          .continueAfterTransition(_hostGameState!)
          .gameState;
    }
  }

  // ─── Host: Play Card ───────────────────────────────────────────────────────

  Future<void> _onPlayCard(
    OnlinePlayCard event,
    Emitter<OnlineState> emit,
  ) async {
    if (!_isHost || _hostGameState == null) return;
    final myEnginePlayer =
        _hostGameState!.players[_hostGameState!.activePlayerIndex];
    final result = _engine.playCard(
      _hostGameState!,
      myEnginePlayer.id,
      event.card,
    );
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

  Future<void> _onGivePunishment(
    OnlineGivePunishment event,
    Emitter<OnlineState> emit,
  ) async {
    if (!_isHost || _hostGameState == null) return;
    final myEnginePlayer =
        _hostGameState!.players[_hostGameState!.activePlayerIndex];
    final result = _engine.givePunishment(
      _hostGameState!,
      myEnginePlayer.id,
      event.card,
    );
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

  Future<void> _onStartNextRound(
    OnlineStartNextRound event,
    Emitter<OnlineState> emit,
  ) async {
    if (!_isHost || _hostGameState == null) return;
    final result = _engine.continueAfterTransition(_hostGameState!);
    _hostGameState = result.gameState;
    _audio.playTurnSwitchSound();
    await _syncStateToRtdb();
    _emitHostGameState(emit);
  }

  Future<void> _onDistributeNewCards(
    OnlineDistributeNewCards event,
    Emitter<OnlineState> emit,
  ) async {
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

  // ─── Host: Player Left — redistribute cards ────────────────────────────────

  Future<void> _onPlayerLeft(
    OnlinePlayerLeft event,
    Emitter<OnlineState> emit,
  ) async {
    if (!_isHost || _hostGameState == null || _room == null) return;

    // Prevent duplicate redistribution for the same player
    if (_redistributedUids.contains(event.playerUid)) return;
    _redistributedUids.add(event.playerUid);

    // Find engine player id for this uid
    final playerUids = _gamePlayers.isNotEmpty
        ? _gamePlayers.map((p) => p.uid).toList()
        : _players.map((p) => p.uid).toList();
    final playerIdx = playerUids.indexOf(event.playerUid);
    if (playerIdx < 0 || playerIdx >= _hostGameState!.players.length) return;

    final enginePlayerId = _hostGameState!.players[playerIdx].id;

    // Remove player from RTDB
    await repository.removePlayer(_room!.roomId, event.playerUid);

    // Redistribute cards in engine
    final result = _engine.redistributePlayerCards(_hostGameState!, enginePlayerId);

    _hostGameState = result.gameState;
    await _syncStateToRtdb();
    _emitHostGameState(emit);
  }

  // ─── Guest: Remote State Updates ──────────────────────────────────────────

  Future<void> _onRemoteGameStateUpdated(
    RemoteGameStateUpdated event,
    Emitter<OnlineState> emit,
  ) async {
    if (_hasLeft) return;
    _lastReceivedGameState = event.data;
    _emitGuestGameState(emit, event.data);
  }

  Future<void> _onMyHandUpdated(
    MyHandUpdated event,
    Emitter<OnlineState> emit,
  ) async {
    if (event.cards.isEmpty && _room != null && _myUid != null && _isGameActive) {
      _wonPlayerUids.add(_myUid!);
      if (!_finishedPlayerUids.contains(_myUid!)) {
        _finishedPlayerUids.add(_myUid!);
      }
      await repository.markPlayerWon(_room!.roomId, _myUid!);
    }
    if (!_isHost && _lastReceivedGameState != null) {
      if (state is OnlineWaitingForTurn || state is OnlinePlayerTurn) {
        _emitGuestGameState(emit, _lastReceivedGameState!);
      }
    }
  }

  // ─── Host: Process Guest's Pending Action ─────────────────────────────────

  Future<void> _onPendingActionReceived(
    PendingActionReceived event,
    Emitter<OnlineState> emit,
  ) async {
    if (!_isHost || _hostGameState == null) return;

    final data = event.data;
    final type = data['type'] as String?;
    final suitStr = data['cardSuit'] as String?;
    final rankStr = data['cardRank'] as String?;
    if (suitStr == null || rankStr == null) return;

    final suit = Suit.values.firstWhere(
      (s) => s.name == suitStr,
      orElse: () => Suit.spades,
    );
    final rank = Rank.values.firstWhere(
      (r) => r.name == rankStr,
      orElse: () => Rank.ace,
    );
    final card = PlayingCard(suit: suit, rank: rank);

    final activeId =
        _hostGameState!.players[_hostGameState!.activePlayerIndex].id;

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
      await repository.clearPendingAction(_room!.roomId);
    }
    _emitHostGameState(emit);
  }

  // ─── Players / Status updates ─────────────────────────────────────────────

  Future<void> _onPlayersUpdated(
    PlayersUpdated event,
    Emitter<OnlineState> emit,
  ) async {
    if (_hasLeft) return;
    _players = event.players;

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in _players) {
      if (p.uid == _myUid) {
        _playerLastHeardLocal[p.uid] = now;
      } else if (p.isOnline) {
        final lastRemote = _playerLastSeenRemote[p.uid];
        if (lastRemote == null || lastRemote != p.lastSeen) {
          _playerLastSeenRemote[p.uid] = p.lastSeen;
          _playerLastHeardLocal[p.uid] = now;
        }
      }
    }

    if (_gamePlayers.isEmpty && _players.isNotEmpty) {
      _gamePlayers = List.from(_players);
    }

    // Sync any players who have won according to RTDB
    for (final p in _players) {
      if (p.hasWon) {
        _wonPlayerUids.add(p.uid);
        if (!_finishedPlayerUids.contains(p.uid)) {
          _finishedPlayerUids.add(p.uid);
        }
      }
    }

    // ─── Active Gameplay Handling ───────────────────────────────────────────
    if (_room != null && (_room!.status == 'in_progress' || _isGameActive)) {
      // 1. Host migration FIRST if current host is offline
      final hostIsOnline = _players.any((p) => p.uid == _room!.hostId && p.isOnline);
      if (!hostIsOnline) {
        final remainingUnfinished = _players
            .where((p) => p.isOnline && !isPlayerWon(p.uid))
            .toList();
        final potentialHosts = remainingUnfinished.isNotEmpty
            ? remainingUnfinished
            : _players.where((p) => p.isOnline).toList();

        if (potentialHosts.isNotEmpty) {
          final newHost = potentialHosts.first;
          if (newHost.uid == _myUid) {
            await repository.claimHost(_room!.roomId, newHost.uid);
            _room = _room!.copyWith(hostId: newHost.uid);
            _isHost = true;
            _subscribeToGame(_room!.roomId);
            await _takeOverHostState();
          }
        }
      }

      // 2. ONLY the HOST may process forfeit for players who quit while still holding cards
      if (_isHost) {
        final offlinePlayers = _players.where((p) => !p.isOnline).toList();
        final missingPlayers = _gamePlayers
            .where((gp) => !_players.any((p) => p.uid == gp.uid))
            .toList();
        final allDeparted = [...offlinePlayers, ...missingPlayers];

        // CRITICAL: Anyone who has already won (empty hand) is NOT forfeiting!
        final forfeitingDeparted = allDeparted
            .where((p) => !isPlayerWon(p.uid))
            .toList();

        if (forfeitingDeparted.isNotEmpty) {
          final donkeyPlayer = forfeitingDeparted.first;
          final donkeyName = donkeyPlayer.name;

          final finishingOrder = <String>[];
          for (final uid in _finishedPlayerUids) {
            final p = _gamePlayers.where((gp) => gp.uid == uid).firstOrNull ??
                _players.where((pl) => pl.uid == uid).firstOrNull;
            final name = p?.name ?? uid;
            if (!finishingOrder.contains(name) && name != donkeyName) {
              finishingOrder.add(name);
            }
          }
          for (final p in _gamePlayers) {
            if (isPlayerWon(p.uid) && !finishingOrder.contains(p.name) && p.name != donkeyName) {
              finishingOrder.add(p.name);
            }
          }
          for (final p in _players) {
            if (p.isOnline && p.uid != donkeyPlayer.uid && !finishingOrder.contains(p.name)) {
              finishingOrder.add(p.name);
            }
          }
          if (!finishingOrder.contains(donkeyName)) {
            finishingOrder.add(donkeyName);
          }

          await repository.forfeitRoom(_room!.roomId, donkeyPlayer.uid, donkeyName);
          await _clearSession();

          emit(OnlineGameFinished(
            donkeyName: donkeyName,
            finishingOrder: finishingOrder,
          ));
          return;
        }
      }

      // 3. If nobody forfeited, check if only 1 unfinished player remains (they lost and are the Donkey!)
      final remainingUnfinishedPlayers = _players
          .where((p) => p.isOnline && !isPlayerWon(p.uid))
          .toList();

      if (remainingUnfinishedPlayers.length == 1 && _gamePlayers.length >= 2) {
        final donkeyPlayer = remainingUnfinishedPlayers.first;
        final donkeyName = donkeyPlayer.name;

        final finishingOrder = <String>[];
        for (final uid in _finishedPlayerUids) {
          final p = _gamePlayers.where((gp) => gp.uid == uid).firstOrNull ??
              _players.where((pl) => pl.uid == uid).firstOrNull;
          final name = p?.name ?? uid;
          if (!finishingOrder.contains(name) && name != donkeyName) {
            finishingOrder.add(name);
          }
        }
        for (final p in _gamePlayers) {
          if (isPlayerWon(p.uid) && !finishingOrder.contains(p.name) && p.name != donkeyName) {
            finishingOrder.add(p.name);
          }
        }
        if (!finishingOrder.contains(donkeyName)) {
          finishingOrder.add(donkeyName);
        }

        if (_isHost) {
          await repository.completeRoom(
            _room!.roomId,
            donkeyUid: donkeyPlayer.uid,
            donkeyName: donkeyName,
          );
        }
        await _clearSession();

        emit(OnlineGameFinished(
          donkeyName: donkeyName,
          finishingOrder: finishingOrder,
        ));
        return;
      }
    }

    // ─── Lobby Handling (Waiting Room) ───────────────────────────────────────
    if (_room != null && _room!.status == 'waiting') {
      final activePlayers = _players.where((p) => p.isOnline).toList();

      if (activePlayers.isEmpty) {
        // Everyone left the lobby -> delete the room
        await repository.deleteRoom(_room!.roomId, _room!.roomCode);
        return;
      }

      final hostIsOnline = activePlayers.any((p) => p.uid == _room!.hostId);
      if (!hostIsOnline) {
        // Host left or is offline: randomly pick from existing active players
        final newHost = (List<OnlinePlayerModel>.from(activePlayers)..shuffle()).first;
        await repository.claimHost(_room!.roomId, newHost.uid);
        _room = _room!.copyWith(hostId: newHost.uid);
        _isHost = (newHost.uid == _myUid);
      }

      // If we are host, automatically remove any offline players from RTDB to free up slots
      if (_isHost) {
        final offlinePlayers = _players.where((p) => !p.isOnline).toList();
        for (final p in offlinePlayers) {
          await repository.removePlayer(_room!.roomId, p.uid);
        }
      }
    }

    if (state is OnlineWaiting) {
      emit(OnlineWaiting(room: _room!, players: _players, isHost: _isHost));
    }
  }

  Future<void> _reconstructHostGameStateFromRtdb() async {
    if (_room == null) return;
    try {
      final rtdbState = await repository.getGameState(_room!.roomId);
      final hands = await repository.getAllHands(_room!.roomId);
      if (rtdbState == null) return;

      final playerOrder = (rtdbState['playerOrder'] as List<Object?>? ?? [])
          .map((e) => e.toString())
          .toList();

      if (playerOrder.isNotEmpty) {
        _gamePlayers = playerOrder.map((uid) {
          return _gamePlayers.firstWhere(
            (p) => p.uid == uid,
            orElse: () => _players.firstWhere(
              (p) => p.uid == uid,
              orElse: () => OnlinePlayerModel(
                uid: uid,
                name: 'Player',
                isOnline: true,
                joinedAt: 0,
              ),
            ),
          );
        }).toList();
      }

      List<Player> enginePlayers = [];
      for (int i = 0; i < playerOrder.length; i++) {
        final uid = playerOrder[i];
        final name = _gamePlayers.firstWhere(
          (p) => p.uid == uid,
          orElse: () => _players.firstWhere(
            (p) => p.uid == uid,
            orElse: () => OnlinePlayerModel(
              uid: uid,
              name: 'Player $i',
              isOnline: true,
              joinedAt: 0,
            ),
          ),
        ).name;
        final playerHand = hands[uid] ?? [];
        enginePlayers.add(Player(id: 'p$i', name: name, hand: playerHand));
      }

      RoundModel? currentRound;
      final roundData = rtdbState['currentRound'];
      if (roundData is Map<Object?, Object?>) {
        currentRound = _parseRound(roundData);
      }

      List<RoundModel> completedRounds = [];
      final completedData = rtdbState['completedRounds'];
      if (completedData is List<Object?>) {
        for (final r in completedData) {
          if (r is Map<Object?, Object?>) {
            completedRounds.add(_parseRound(r));
          }
        }
      }

      final activeIdx = rtdbState['activePlayerIndex'] as int? ?? 0;

      _hostGameState = engine.GameState(
        players: enginePlayers,
        activePlayerIndex: activeIdx,
        currentRound: currentRound,
        completedRounds: completedRounds,
        phase: GamePhase.playerTurn,
        history: MoveHistory(),
      );
    } catch (_) {}
  }

  Future<void> _onRestartRoom(
    OnlineRestartRoom event,
    Emitter<OnlineState> emit,
  ) async {
    if (_room == null || _myUid == null) return;
    try {
      emit(const OnlineLoading('Restarting game...'));
      final currentRoom = await repository.getActiveRoom(_room!.roomId);
      String hostId;
      if (currentRoom != null && currentRoom.status == 'waiting') {
        // Room was already restarted: rejoin as guest (pass name so it persists)
        await repository.rejoinRoom(_room!.roomId, _myUid!, _myName);
        hostId = currentRoom.hostId;
      } else {
        // First one to return to lobby! Make this player the host!
        await repository.restartRoom(_room!.roomId, _myUid!, _myName);
        hostId = _myUid!;
      }
      _isHost = (hostId == _myUid);
      _hostGameState = null;
      _lastReceivedGameState = null;
      _redistributedUids.clear();
      _subscribeToLobby(_room!.roomId);
      await _saveSession(_room!.roomId, _room!.roomCode, _myName ?? 'Player', _myUid!);

      _room = OnlineRoomModel(
        roomId: _room!.roomId,
        roomCode: _room!.roomCode,
        hostId: hostId,
        status: 'waiting',
        maxPlayers: _room!.maxPlayers,
        createdAt: _room!.createdAt,
      );

      _players = [
        OnlinePlayerModel(
          uid: _myUid!,
          name: _myName ?? 'Player',
          isOnline: true,
          joinedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ];

      emit(OnlineWaiting(room: _room!, players: _players, isHost: _isHost));
    } catch (e) {
      emit(OnlineError(e.toString()));
    }
  }

  void _onRoomStatusChanged(
    RoomStatusChanged event,
    Emitter<OnlineState> emit,
  ) {
    if (_hasLeft) return;
    if (_room != null) {
      _room = _room!.copyWith(status: event.status);
    }
    if (event.status == 'in_progress' && !_isHost) {
      if (_gamePlayers.isEmpty && _players.isNotEmpty) {
        _gamePlayers = List.from(_players);
      }
      _subscribeToGame(_room!.roomId);
    }
  }

  void _onRoomMetaChanged(
    RoomMetaChanged event,
    Emitter<OnlineState> emit,
  ) {
    if (_hasLeft) return;
    final meta = event.meta;
    final status = meta['status'] as String? ?? 'waiting';
    final hostId = meta['hostId'] as String?;

    if (_room != null) {
      _room = _room!.copyWith(
        status: status,
        hostId: hostId ?? _room!.hostId,
      );
      _isHost = (_room!.hostId == _myUid);
    }

    if (status == 'in_progress') {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('active_game_in_progress', 'true');
      });
      if (_isHost && _hostGameState == null) {
        _subscribeToGame(_room!.roomId);
        _takeOverHostState();
      } else if (!_isHost) {
        if (_gamePlayers.isEmpty && _players.isNotEmpty) {
          _gamePlayers = List.from(_players);
        }
        _subscribeToGame(_room!.roomId);
      }
    } else if (status == 'waiting') {
      if (state is OnlineWaiting) {
        emit(OnlineWaiting(room: _room!, players: _players, isHost: _isHost));
      }
    }
  }

  Future<void> _takeOverHostState() async {
    if (_room == null) return;
    try {
      final hands = await repository.getAllHands(_room!.roomId);
      final data = _lastReceivedGameState;
      if (data == null) return;
      final playerOrder = (data['playerOrder'] as List<Object?>? ?? [])
          .map((e) => e.toString())
          .toList();
      final activeIdx = data['activePlayerIndex'] as int? ?? 0;
      final phaseStr = data['phase'] as String? ?? 'playerTurn';

      final enginePlayers = <Player>[];
      for (int i = 0; i < playerOrder.length; i++) {
        final uid = playerOrder[i];
        final name = _gamePlayers.firstWhere(
          (p) => p.uid == uid,
          orElse: () => _players.firstWhere(
            (p) => p.uid == uid,
            orElse: () => OnlinePlayerModel(
              uid: uid,
              name: 'Player $i',
              isOnline: true,
              joinedAt: 0,
            ),
          ),
        ).name;
        final hand = hands[uid] ?? [];
        enginePlayers.add(Player(id: 'p$i', name: name, hand: hand));
      }

      final finishedUids = (data['finishedPlayerUids'] as List<Object?>? ?? [])
          .map((e) => e.toString())
          .toList();
      final finishedIds = finishedUids.map((uid) {
        final idx = playerOrder.indexOf(uid);
        return idx >= 0 ? 'p$idx' : uid;
      }).toList();

      for (int i = 0; i < enginePlayers.length; i++) {
        if (enginePlayers[i].hand.isEmpty && !finishedIds.contains('p$i')) {
          finishedIds.add('p$i');
        }
      }

      final completedRoundsRaw = data['completedRounds'] as List<Object?>? ?? [];
      final completedRounds = <RoundModel>[];
      for (final cr in completedRoundsRaw) {
        if (cr is Map<Object?, Object?>) {
          completedRounds.add(_parseRound(cr));
        }
      }

      RoundModel? currentRound;
      if (data['currentRound'] is Map<Object?, Object?>) {
        currentRound = _parseRound(data['currentRound'] as Map<Object?, Object?>);
      }

      final phase = GamePhase.values.firstWhere(
        (e) => e.name == phaseStr,
        orElse: () => GamePhase.playerTurn,
      );

      _hostGameState = engine.GameState(
        players: enginePlayers,
        activePlayerIndex: activeIdx,
        phase: phase,
        completedRounds: completedRounds,
        currentRound: currentRound,
        finishedPlayerIds: finishedIds,
      );
      _advanceIfTurnTransition();
      await _syncStateToRtdb();
    } catch (e) {
      debugPrint('Error taking over host state: $e');
    }
  }

  // ─── Sync / Emit Helpers ───────────────────────────────────────────────────

  Future<void> _syncStateToRtdb() async {
    if (!_isHost || _hostGameState == null || _room == null) return;
    final playerUids = _gamePlayers.isNotEmpty
        ? _gamePlayers.map((p) => p.uid).toList()
        : _players.map((p) => p.uid).toList();
    final gsMap = _buildPublicGameState(_hostGameState!, playerUids);
    final handsPerPlayer = <String, List<Map<String, dynamic>>>{};
    final newlyWonUids = <String>[];
    for (
      int i = 0;
      i < _hostGameState!.players.length && i < playerUids.length;
      i++
    ) {
      final uid = playerUids[i];
      final hand = _hostGameState!.players[i].hand;
      handsPerPlayer[uid] = hand
          .map((c) => c.toJson())
          .toList();
      if (hand.isEmpty || _wonPlayerUids.contains(uid)) {
        newlyWonUids.add(uid);
        _wonPlayerUids.add(uid);
      }
    }
    await repository.writeGameState(
      roomId: _room!.roomId,
      gameState: gsMap,
      handsPerPlayer: handsPerPlayer,
      wonPlayerUids: newlyWonUids,
    );
  }

  void _emitHostGameState(Emitter<OnlineState> emit) {
    if (_hostGameState == null) return;
    if (_hasWon) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('active_player_has_won', 'true');
      });
    }
    final gs = _hostGameState!;
    final activeIdx = gs.activePlayerIndex;
    final activeEnginePlayer = gs.players[activeIdx];
    final playerUids = _gamePlayers.isNotEmpty
        ? _gamePlayers.map((p) => p.uid).toList()
        : _players.map((p) => p.uid).toList();

    final myIdx = playerUids.indexOf(_myUid!);
    final myEnginePlayer = myIdx >= 0 && myIdx < gs.players.length
        ? gs.players[myIdx]
        : gs.players[0];

    final isMyTurn = activeEnginePlayer.id == myEnginePlayer.id;

    final Map<String, String> pNames = {};
    for (int i = 0; i < playerUids.length; i++) {
      pNames['p$i'] = _gamePlayers.isNotEmpty
          ? _gamePlayers.firstWhere(
              (p) => p.uid == playerUids[i],
              orElse: () => OnlinePlayerModel(
                uid: playerUids[i],
                name: 'Player $i',
                isOnline: true,
                joinedAt: 0,
              ),
            ).name
          : _players
              .firstWhere(
                (p) => p.uid == playerUids[i],
                orElse: () => OnlinePlayerModel(
                  uid: playerUids[i],
                  name: 'Player $i',
                  isOnline: true,
                  joinedAt: 0,
                ),
              )
              .name;
    }

    switch (gs.phase) {
      case GamePhase.playerTurn:
      case GamePhase.turnTransition:
        emit(
          OnlinePlayerTurn(
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
            playerNames: pNames,
            isHost: true,
            isFirstTurn: gs.completedRounds.isEmpty && gs.currentRound == null,
            unendingLoopDetected: gs.unendingLoopDetected,
            myEngineId: myEnginePlayer.id,
          ),
        );
        break;
      case GamePhase.punishmentSelection:
        final targetId = _punishmentRules.targetOfPunishment(
          gs.currentRound!.playedCards,
        );
        final targetName = gs.players.firstWhere((p) => p.id == targetId).name;
        if (isMyTurn) {
          emit(
            OnlinePunishmentNeeded(
              myHand: myEnginePlayer.hand,
              receivingPlayerName: targetName,
            ),
          );
        }
        break;
      case GamePhase.roundEnd:
        final completedRound = gs.completedRounds.last;
        final leaderId = _moveRules.roundLeaderId(completedRound);
        final leaderName = gs.players.firstWhere((p) => p.id == leaderId).name;
        String? punishReceiverName;
        String? punishReceiverUid;
        if (completedRound.punishmentCard != null &&
            completedRound.winnerId != null) {
          final targetId = _punishmentRules.targetOfPunishment(
            completedRound.playedCards,
          );
          final targetEngineIdx = int.tryParse(targetId.replaceAll('p', ''));
          if (targetEngineIdx != null && targetEngineIdx < playerUids.length) {
            punishReceiverUid = playerUids[targetEngineIdx];
            punishReceiverName = gs.players
                .firstWhere((p) => p.id == targetId)
                .name;
            if (punishReceiverUid == _myUid) {
              _audio.playPunishSound();
            }
          }
        }
        emit(
          OnlineRoundCompleted(
            nextRoundLeaderName: leaderName,
            completedRound: completedRound,
            playerNames: pNames,
            isHost: true,
            punishmentCard: completedRound.punishmentCard,
            punishmentReceiverName: punishReceiverName,
            punishmentReceiverUid: punishReceiverUid,
          ),
        );
        break;
      case GamePhase.gameOver:
        final donkeyId = gs.donkeyPlayerId ?? '';
        final donkeyPlayer = gs.players.firstWhere(
          (p) => p.id == donkeyId,
          orElse: () => gs.players.last,
        );
        final donkeyName = donkeyPlayer.name;
        final finishing = gs.finishedPlayerIds
            .map((id) => gs.players.firstWhere((p) => p.id == id, orElse: () => Player(id: id, name: id, hand: [])).name)
            .toList();
        if (!finishing.contains(donkeyName)) {
          finishing.add(donkeyName);
        }
        repository.completeRoom(_room!.roomId);
        _clearSession();
        emit(
          OnlineGameFinished(donkeyName: donkeyName, finishingOrder: finishing),
        );
        break;
      case GamePhase.dealing:
        break;
    }
  }

  void _emitGuestGameState(
    Emitter<OnlineState> emit,
    Map<Object?, Object?> data,
  ) {
    final phase = data['phase'] as String? ?? 'playerTurn';
    final activeIdx = data['activePlayerIndex'] as int? ?? 0;
    final playerOrder = (data['playerOrder'] as List<Object?>? ?? [])
        .map((e) => e.toString())
        .toList();

    if (playerOrder.isEmpty) return;

    final finishedUids = (data['finishedPlayerUids'] as List<Object?>? ?? [])
        .map((e) => e.toString())
        .toList();
    _finishedPlayerUids = finishedUids;

    if (_hasWon) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString('active_player_has_won', 'true');
      });
    }

    final activeUid = activeIdx < playerOrder.length
        ? playerOrder[activeIdx]
        : '';
    final activePlayer = _players.firstWhere(
      (p) => p.uid == activeUid,
      orElse: () => OnlinePlayerModel(
        uid: '',
        name: 'Unknown',
        isOnline: true,
        joinedAt: 0,
      ),
    );
    final isMyTurn = activeUid == _myUid;

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

    final Map<String, String> pNames = {};
    for (int i = 0; i < playerOrder.length; i++) {
      final uid = playerOrder[i];
      pNames['p$i'] = _gamePlayers.firstWhere(
        (p) => p.uid == uid,
        orElse: () => _players.firstWhere(
          (p) => p.uid == uid,
          orElse: () => OnlinePlayerModel(
            uid: uid,
            name: 'Player',
            isOnline: true,
            joinedAt: 0,
          ),
        ),
      ).name;
    }

    final myIdx = _myUid != null ? playerOrder.indexOf(_myUid!) : -1;

    switch (phase) {
      case 'playerTurn':
      case 'turnTransition':
        if (isMyTurn) {
          emit(
            OnlinePlayerTurn(
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
              playerNames: pNames,
              isHost: false,
              isFirstTurn: completedRounds.isEmpty && currentRound == null,
              unendingLoopDetected:
                  data['unendingLoopDetected'] as bool? ?? false,
              myEngineId: 'p$myIdx',
            ),
          );
        } else {
          emit(
            OnlineWaitingForTurn(
              myName: _myName ?? '',
              activePlayerName: activePlayer.name,
              myHand: _myHand,
              currentRound: currentRound,
              playerNames: pNames,
              isHost: false,
              myEngineId: 'p$myIdx',
              unendingLoopDetected: data['unendingLoopDetected'] as bool? ?? false,
            ),
          );
        }
        break;
      case 'punishmentSelection':
        if (isMyTurn) {
          final playedCards = currentRound?.playedCards ?? [];
          final targetId = playedCards.isNotEmpty
              ? _punishmentRules.targetOfPunishment(playedCards)
              : '';
          final targetUid =
              targetId.isNotEmpty &&
                  playerOrder.length >
                      int.tryParse(targetId.replaceAll('p', ''))!
              ? playerOrder[int.parse(targetId.replaceAll('p', ''))]
              : '';
          final targetPlayer = _players.firstWhere(
            (p) => p.uid == targetUid,
            orElse: () => OnlinePlayerModel(
              uid: '',
              name: 'Player',
              isOnline: true,
              joinedAt: 0,
            ),
          );
          emit(
            OnlinePunishmentNeeded(
              myHand: _myHand,
              receivingPlayerName: targetPlayer.name,
            ),
          );
        } else {
          emit(
            OnlineWaitingForTurn(
              myName: _myName ?? '',
              activePlayerName: activePlayer.name,
              myHand: _myHand,
              currentRound: currentRound,
              playerNames: pNames,
              isHost: false,
              myEngineId: 'p$myIdx',
            ),
          );
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
                playedCards: [],
              );
        String? punishReceiverName;
        String? punishReceiverUid;
        if (lastRound.punishmentCard != null) {
          final completedRaw = data['completedRounds'];
          if (completedRaw is List<Object?> && completedRaw.isNotEmpty) {
            final lastRaw = completedRaw.last;
            if (lastRaw is Map<Object?, Object?>) {
              punishReceiverUid = lastRaw['punishmentReceiverUid'] as String?;
            }
          }
          if (punishReceiverUid != null) {
            punishReceiverName = _players
                .firstWhere(
                  (p) => p.uid == punishReceiverUid,
                  orElse: () => OnlinePlayerModel(
                    uid: '',
                    name: 'Player',
                    isOnline: true,
                    joinedAt: 0,
                  ),
                )
                .name;
          }
          if (punishReceiverUid == _myUid) {
            _audio.playPunishSound();
          }
        }
        emit(
          OnlineRoundCompleted(
            nextRoundLeaderName: winnerName,
            completedRound: lastRound,
            playerNames: pNames,
            isHost: false,
            punishmentCard: lastRound.punishmentCard,
            punishmentReceiverName: punishReceiverName,
            punishmentReceiverUid: punishReceiverUid,
          ),
        );
        break;
      case 'gameOver':
        if (_hasLeft) return;
        final donkeyUid = data['donkeyPlayerUid'] as String? ?? '';
        final donkeyNameFromData = data['donkeyPlayerName'] as String?;
        final donkeyPlayer = (donkeyNameFromData != null && donkeyNameFromData.isNotEmpty)
            ? OnlinePlayerModel(uid: donkeyUid, name: donkeyNameFromData, isOnline: false, joinedAt: 0)
            : _gamePlayers.firstWhere(
                (p) => p.uid == donkeyUid,
                orElse: () => _players.firstWhere(
                  (p) => p.uid == donkeyUid,
                  orElse: () => OnlinePlayerModel(
                    uid: donkeyUid,
                    name: 'Player',
                    isOnline: false,
                    joinedAt: 0,
                  ),
                ),
              );
        final finishedUids =
            (data['finishedPlayerUids'] as List<Object?>? ?? [])
                .map((e) => e.toString())
                .toList();
        final finishing = <String>[];
        for (final uid in finishedUids) {
          final p = _gamePlayers.where((gp) => gp.uid == uid).firstOrNull ??
              _players.where((pl) => pl.uid == uid).firstOrNull;
          final name = p?.name ?? uid;
          if (!finishing.contains(name) && name != donkeyPlayer.name) {
            finishing.add(name);
          }
        }
        for (final uid in _wonPlayerUids) {
          final p = _gamePlayers.where((gp) => gp.uid == uid).firstOrNull ??
              _players.where((pl) => pl.uid == uid).firstOrNull;
          final name = p?.name ?? uid;
          if (!finishing.contains(name) && name != donkeyPlayer.name) {
            finishing.add(name);
          }
        }
        for (final p in _gamePlayers) {
          if (p.hasWon && !finishing.contains(p.name) && p.name != donkeyPlayer.name) {
            finishing.add(p.name);
          }
        }
        if (!finishing.contains(donkeyPlayer.name)) {
          finishing.add(donkeyPlayer.name);
        }
        if (_isHost && _room != null) {
          repository.completeRoom(
            _room!.roomId,
            donkeyUid: donkeyPlayer.uid,
            donkeyName: donkeyPlayer.name,
          );
        }
        _clearSession();
        _cancelAllSubscriptions();
        emit(
          OnlineGameFinished(
            donkeyName: donkeyPlayer.name,
            finishingOrder: finishing,
          ),
        );
        break;
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildPublicGameState(
    engine.GameState gs,
    List<String> playerUids,
  ) {
    final phase = gs.phase == GamePhase.turnTransition
        ? 'playerTurn'
        : gs.phase.name;

    Map<String, dynamic>? roundMap;
    if (gs.currentRound != null) {
      roundMap = _roundToMap(gs.currentRound!, playerUids);
    }

    final completedMaps = gs.completedRounds
        .map((r) => _roundToMap(r, playerUids))
        .toList();

    String lastRoundWinnerUid = '';
    if (gs.completedRounds.isNotEmpty) {
      final leaderId = _moveRules.roundLeaderId(gs.completedRounds.last);
      final leaderIdx = gs.players.indexWhere((p) => p.id == leaderId);
      if (leaderIdx >= 0 && leaderIdx < playerUids.length) {
        lastRoundWinnerUid = playerUids[leaderIdx];
      }
    }

    String? donkeyUid;
    String? donkeyName;
    if (gs.donkeyPlayerId != null) {
      final donkeyIdx = gs.players.indexWhere((p) => p.id == gs.donkeyPlayerId);
      if (donkeyIdx >= 0 && donkeyIdx < playerUids.length) {
        donkeyUid = playerUids[donkeyIdx];
        donkeyName = gs.players[donkeyIdx].name;
      }
    }

    final finishedUids = <String>[];
    for (final id in gs.finishedPlayerIds) {
      final idx = gs.players.indexWhere((p) => p.id == id);
      final uid = idx >= 0 && idx < playerUids.length ? playerUids[idx] : id;
      if (!finishedUids.contains(uid)) finishedUids.add(uid);
    }
    for (int i = 0; i < gs.players.length && i < playerUids.length; i++) {
      if (gs.players[i].hand.isEmpty) {
        final uid = playerUids[i];
        if (!finishedUids.contains(uid)) finishedUids.add(uid);
      }
    }
    for (final uid in _wonPlayerUids) {
      if (!finishedUids.contains(uid)) finishedUids.add(uid);
    }
    _finishedPlayerUids = finishedUids;

    return {
      'phase': phase,
      'activePlayerIndex': gs.activePlayerIndex,
      'playerOrder': playerUids,
      'currentRound': roundMap,
      'completedRounds': completedMaps,
      'lastRoundWinnerId': lastRoundWinnerUid,
      'donkeyPlayerUid': donkeyUid,
      'donkeyPlayerName': donkeyName,
      'finishedPlayerUids': finishedUids,
      'unendingLoopDetected': gs.unendingLoopDetected,
    };
  }

  Map<String, dynamic> _roundToMap(RoundModel r, List<String> playerUids) {
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
      'playedCards': r.playedCards
          .map((pc) => {'playerId': pc.playerId, 'card': pc.card.toJson()})
          .toList(),
      if (r.punishmentCard != null)
        'punishmentCard': r.punishmentCard!.toJson(),
      if (punishmentReceiverUid != null)
        'punishmentReceiverUid': punishmentReceiverUid,
    };
  }

  RoundModel _parseRound(Map<Object?, Object?> data) {
    final suitStr = data['suit'] as String? ?? 'spades';
    final suit = Suit.values.firstWhere(
      (s) => s.name == suitStr,
      orElse: () => Suit.spades,
    );
    final playedCardsRaw = data['playedCards'] as List<Object?>? ?? [];
    final playedCards = playedCardsRaw.whereType<Map<Object?, Object?>>().map((
      pc,
    ) {
      final cardData = pc['card'] as Map<Object?, Object?>? ?? {};
      final m = cardData.map((k, v) => MapEntry(k.toString(), v));
      return PlayedCard(
        playerId: pc['playerId'] as String? ?? '',
        card: PlayingCard.fromJson(m),
      );
    }).toList();
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

  Future<void> _onLeaveRoom(
    OnlineLeaveRoom event,
    Emitter<OnlineState> emit,
  ) async {
    _hasLeft = true;
    _cancelAllSubscriptions();
    final roomId = _room?.roomId;
    final uid = _myUid;
    final name = _myName ?? 'Player';
    final wasGameActive = _isGameActive;
    final hasAlreadyWon = _hasWon;
    final wasHost = _isHost;
    final activePlayers = List<OnlinePlayerModel>.from(_players);

    _room = null;
    _myUid = null;
    _myName = null;
    _isHost = false;
    _hostGameState = null;
    _players = [];
    _gamePlayers = [];
    _redistributedUids.clear();
    await _clearSession();
    emit(OnlineInitial());

    if (roomId != null && uid != null) {
      if (wasGameActive) {
        if (hasAlreadyWon) {
          // Player already finished and won! They can leave safely without becoming donkey.
          await repository.markPlayerWon(roomId, uid);
          if (wasHost) {
            final otherOnline = activePlayers.where((p) => p.uid != uid && p.isOnline).toList();
            if (otherOnline.isNotEmpty) {
              final nextHost = otherOnline.firstWhere(
                (p) => !isPlayerWon(p.uid),
                orElse: () => otherOnline.first,
              );
              await repository.claimHost(roomId, nextHost.uid);
            }
          }
          await repository.leaveRoom(roomId, uid);
        } else {
          // Leaving an active game before winning forfeits and makes the player the donkey!
          await repository.forfeitRoom(roomId, uid, name);
        }
      } else {
        await repository.leaveRoom(roomId, uid);
      }
    }
  }

  void _cancelAllSubscriptions() {
    _stopHeartbeat();
    _playerLastHeardLocal.clear();
    _playerLastSeenRemote.clear();
    _finishedPlayerUids.clear();
    _wonPlayerUids.clear();
    _playersSub?.cancel();
    _statusSub?.cancel();
    _gameStateSub?.cancel();
    _pendingActionSub?.cancel();
    _myHandSub?.cancel();
    _connectionSub?.cancel();
    _wonPlayersSub?.cancel();
  }

  @override
  Future<void> close() {
    _cancelAllSubscriptions();
    return super.close();
  }
}
