import 'package:equatable/equatable.dart';
import '../../models/online_room_model.dart';
import '../../models/card_model.dart';
import '../../models/round_model.dart';
import '../../models/enums/suit.dart';
import '../../models/played_card.dart';

abstract class OnlineState extends Equatable {
  const OnlineState();
  @override
  List<Object?> get props => [];
}

class OnlineInitial extends OnlineState {}

class OnlineLoading extends OnlineState {
  final String message;
  const OnlineLoading([this.message = 'Loading...']);
  @override
  List<Object?> get props => [message];
}

class OnlineError extends OnlineState {
  final String message;
  const OnlineError(this.message);
  @override
  List<Object?> get props => [message];
}

/// In the waiting lobby (both host and joining players)
class OnlineWaiting extends OnlineState {
  final OnlineRoomModel room;
  final List<OnlinePlayerModel> players;
  final bool isHost;

  const OnlineWaiting({
    required this.room,
    required this.players,
    required this.isHost,
  });

  bool get canStart => players.length >= 2 && isHost;

  @override
  List<Object?> get props => [room, players, isHost];
}

/// Shared base for in-game states (host and guest both use these)
/// The key difference: isMyTurn determines who can interact.
class OnlinePlayerTurn extends OnlineState {
  final String myName;
  final String activePlayerName;
  final bool isMyTurn;
  final List<PlayingCard> myHand;
  final RoundModel? currentRound;
  final Suit? currentSuit;
  final PlayedCard? highestCard;
  final List<OnlinePlayerModel> allPlayers;
  final Map<String, String> playerNames;
  final bool isHost;
  final bool isFirstTurn;
  final bool unendingLoopDetected;
  final String myEngineId;

  const OnlinePlayerTurn({
    required this.myName,
    required this.activePlayerName,
    required this.isMyTurn,
    required this.myHand,
    this.currentRound,
    this.currentSuit,
    this.highestCard,
    required this.allPlayers,
    required this.playerNames,
    required this.isHost,
    this.isFirstTurn = false,
    this.unendingLoopDetected = false,
    required this.myEngineId,
  });

  @override
  List<Object?> get props => [
        myName,
        activePlayerName,
        isMyTurn,
        myHand,
        currentRound,
        currentSuit,
        highestCard,
        allPlayers,
        playerNames,
        isHost,
        isFirstTurn,
        unendingLoopDetected,
        myEngineId,
      ];
}

class OnlineRoundCompleted extends OnlineState {
  final String nextRoundLeaderName;
  final RoundModel completedRound;
  final Map<String, String> playerNames;
  final bool isHost;
  // Punishment info — non-null when this round ended via punishment
  final PlayingCard? punishmentCard;
  final String? punishmentReceiverName;
  final String? punishmentReceiverUid; // only non-null for online; used to show toast only to receiver

  const OnlineRoundCompleted({
    required this.nextRoundLeaderName,
    required this.completedRound,
    required this.playerNames,
    required this.isHost,
    this.punishmentCard,
    this.punishmentReceiverName,
    this.punishmentReceiverUid,
  });

  @override
  List<Object?> get props => [nextRoundLeaderName, completedRound, playerNames, isHost, punishmentCard, punishmentReceiverName, punishmentReceiverUid];
}

class OnlinePunishmentNeeded extends OnlineState {
  final List<PlayingCard> myHand;
  final String receivingPlayerName;

  const OnlinePunishmentNeeded({
    required this.myHand,
    required this.receivingPlayerName,
  });

  @override
  List<Object?> get props => [myHand, receivingPlayerName];
}

class OnlineGameFinished extends OnlineState {
  final String donkeyName;
  final List<String> finishingOrder;

  const OnlineGameFinished({
    required this.donkeyName,
    required this.finishingOrder,
  });

  @override
  List<Object?> get props => [donkeyName, finishingOrder];
}

/// Waiting for the remote player to take their turn
class OnlineWaitingForTurn extends OnlineState {
  final String myName;
  final String activePlayerName;
  final List<PlayingCard> myHand;
  final RoundModel? currentRound;
  final Map<String, String> playerNames;
  final bool isHost;
  final String myEngineId;
  final bool unendingLoopDetected;

  const OnlineWaitingForTurn({
    required this.myName,
    required this.activePlayerName,
    required this.myHand,
    this.currentRound,
    required this.playerNames,
    required this.isHost,
    required this.myEngineId,
    this.unendingLoopDetected = false,
  });

  @override
  List<Object?> get props => [
        myName,
        activePlayerName,
        myHand,
        currentRound,
        playerNames,
        isHost,
        myEngineId,
        unendingLoopDetected,
      ];
}

class OnlineRedistributingCards extends OnlineState {
  final String disconnectedPlayerName;

  const OnlineRedistributingCards({required this.disconnectedPlayerName});

  @override
  List<Object?> get props => [disconnectedPlayerName];
}

