import 'package:equatable/equatable.dart';
import 'game_state.dart';

enum MoveType {
  cardPlayed,
  punishmentRequired,
  punishmentCompleted,
  roundCompleted,
  gameCompleted,
  invalidMove,
}

class MoveResult extends Equatable {
  final GameState gameState;
  final MoveType moveType;
  final String? message;

  const MoveResult({
    required this.gameState,
    required this.moveType,
    this.message,
  });

  MoveResult copyWith({
    GameState? gameState,
    MoveType? moveType,
    String? message,
  }) {
    return MoveResult(
      gameState: gameState ?? this.gameState,
      moveType: moveType ?? this.moveType,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [gameState, moveType, message];
}
