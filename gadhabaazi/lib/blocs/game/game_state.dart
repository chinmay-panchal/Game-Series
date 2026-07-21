import 'package:equatable/equatable.dart';
import '../../models/player_model.dart';
import '../../models/round_model.dart';
import '../../models/played_card.dart';
import '../../models/enums/suit.dart';
import '../../engine/history/move_history.dart';

abstract class GameBlocState extends Equatable {
  const GameBlocState();

  @override
  List<Object?> get props => [];
}

class GameInitial extends GameBlocState {}

class GameDealing extends GameBlocState {
  final List<Player> players;
  const GameDealing(this.players);

  @override
  List<Object?> get props => [players];
}

class GamePlayerTurn extends GameBlocState {
  final Player activePlayer;
  final List<Player> otherPlayers;
  final RoundModel? currentRound;
  final Suit? currentSuit;
  final PlayedCard? highestCard;
  final bool isHandRevealed;
  final bool isFirstTurn;

  const GamePlayerTurn({
    required this.activePlayer,
    required this.otherPlayers,
    this.currentRound,
    this.currentSuit,
    this.highestCard,
    this.isHandRevealed = false,
    this.isFirstTurn = false,
  });

  @override
  List<Object?> get props => [activePlayer, otherPlayers, currentRound, currentSuit, highestCard, isHandRevealed, isFirstTurn];
}

class GamePunishmentSelection extends GameBlocState {
  final Player givingPlayer;
  final String receivingPlayerName;

  const GamePunishmentSelection({
    required this.givingPlayer,
    required this.receivingPlayerName,
  });

  @override
  List<Object?> get props => [givingPlayer, receivingPlayerName];
}

class GameRoundCompleted extends GameBlocState {
  final String nextRoundLeaderName;
  final RoundModel completedRound;

  const GameRoundCompleted({
    required this.nextRoundLeaderName,
    required this.completedRound,
  });

  @override
  List<Object?> get props => [nextRoundLeaderName, completedRound];
}

class GameFinished extends GameBlocState {
  final String donkeyName;
  final List<String> finishingOrder;
  final MoveHistory history;

  const GameFinished({
    required this.donkeyName,
    required this.finishingOrder,
    required this.history,
  });

  @override
  List<Object?> get props => [donkeyName, finishingOrder, history];
}

class GameError extends GameBlocState {
  final String message;
  const GameError(this.message);

  @override
  List<Object?> get props => [message];
}
