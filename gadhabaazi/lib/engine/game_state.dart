import 'package:equatable/equatable.dart';
import '../../models/player_model.dart';
import '../../models/round_model.dart';
import '../../models/enums/game_phase.dart';
import 'history/move_history.dart';

class GameState extends Equatable {
  final List<Player> players;
  final List<RoundModel> completedRounds;
  final RoundModel? currentRound;
  final int activePlayerIndex;
  final GamePhase phase;
  
  /// The last player remaining with cards. Null until the game ends.
  final String? donkeyPlayerId;
  
  /// Players who have already emptied their hand, in finishing order.
  final List<String> finishedPlayerIds;
  
  final MoveHistory history;
  
  /// Track unending loops for 2-player games
  final int unendingLoopCounter;
  final int lastTotalCardsCount;
  final bool unendingLoopDetected;

  const GameState({
    required this.players,
    this.completedRounds = const [],
    this.currentRound,
    required this.activePlayerIndex,
    required this.phase,
    this.donkeyPlayerId,
    this.finishedPlayerIds = const [],
    this.history = const MoveHistory(),
    this.unendingLoopCounter = 0,
    this.lastTotalCardsCount = 0,
    this.unendingLoopDetected = false,
  });

  GameState copyWith({
    List<Player>? players,
    List<RoundModel>? completedRounds,
    RoundModel? currentRound,
    bool clearCurrentRound = false,
    int? activePlayerIndex,
    GamePhase? phase,
    String? donkeyPlayerId,
    List<String>? finishedPlayerIds,
    MoveHistory? history,
    int? unendingLoopCounter,
    int? lastTotalCardsCount,
    bool? unendingLoopDetected,
  }) {
    return GameState(
      players: players ?? this.players,
      completedRounds: completedRounds ?? this.completedRounds,
      currentRound: clearCurrentRound ? null : (currentRound ?? this.currentRound),
      activePlayerIndex: activePlayerIndex ?? this.activePlayerIndex,
      phase: phase ?? this.phase,
      donkeyPlayerId: donkeyPlayerId ?? this.donkeyPlayerId,
      finishedPlayerIds: finishedPlayerIds ?? this.finishedPlayerIds,
      history: history ?? this.history,
      unendingLoopCounter: unendingLoopCounter ?? this.unendingLoopCounter,
      lastTotalCardsCount: lastTotalCardsCount ?? this.lastTotalCardsCount,
      unendingLoopDetected: unendingLoopDetected ?? this.unendingLoopDetected,
    );
  }

  Map<String, dynamic> toJson() => {
    'players': players.map((p) => p.toJson()).toList(),
    'completedRounds': completedRounds.map((r) => r.toJson()).toList(),
    'currentRound': currentRound?.toJson(),
    'activePlayerIndex': activePlayerIndex,
    'phase': phase.name,
    'donkeyPlayerId': donkeyPlayerId,
    'finishedPlayerIds': finishedPlayerIds,
    'history': history.toJson(),
    'unendingLoopCounter': unendingLoopCounter,
    'lastTotalCardsCount': lastTotalCardsCount,
    'unendingLoopDetected': unendingLoopDetected,
  };

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      players: (json['players'] as List<dynamic>)
          .map((p) => Player.fromJson(p as Map<String, dynamic>))
          .toList(),
      completedRounds: (json['completedRounds'] as List<dynamic>)
          .map((r) => RoundModel.fromJson(r as Map<String, dynamic>))
          .toList(),
      currentRound: json['currentRound'] != null
          ? RoundModel.fromJson(json['currentRound'] as Map<String, dynamic>)
          : null,
      activePlayerIndex: json['activePlayerIndex'] as int,
      phase: GamePhase.values.firstWhere((e) => e.name == json['phase']),
      donkeyPlayerId: json['donkeyPlayerId'] as String?,
      finishedPlayerIds: (json['finishedPlayerIds'] as List<dynamic>).cast<String>(),
      history: MoveHistory.fromJson(json['history'] as Map<String, dynamic>),
      unendingLoopCounter: json['unendingLoopCounter'] as int? ?? 0,
      lastTotalCardsCount: json['lastTotalCardsCount'] as int? ?? 0,
      unendingLoopDetected: json['unendingLoopDetected'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        players,
        completedRounds,
        currentRound,
        activePlayerIndex,
        phase,
        donkeyPlayerId,
        finishedPlayerIds,
        history,
        unendingLoopCounter,
        lastTotalCardsCount,
        unendingLoopDetected,
      ];
}
