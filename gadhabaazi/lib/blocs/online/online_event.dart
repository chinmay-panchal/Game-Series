import 'package:equatable/equatable.dart';
import '../../models/online_room_model.dart';
import '../../models/card_model.dart';

abstract class OnlineEvent extends Equatable {
  const OnlineEvent();
  @override
  List<Object?> get props => [];
}

class CreateRoom extends OnlineEvent {
  final String hostName;
  final int maxPlayers;
  const CreateRoom({required this.hostName, required this.maxPlayers});
  @override
  List<Object?> get props => [hostName, maxPlayers];
}

class JoinRoom extends OnlineEvent {
  final String roomCode;
  final String playerName;
  const JoinRoom({required this.roomCode, required this.playerName});
  @override
  List<Object?> get props => [roomCode, playerName];
}

class HostStartGame extends OnlineEvent {}

class OnlinePlayCard extends OnlineEvent {
  final PlayingCard card;
  const OnlinePlayCard(this.card);
  @override
  List<Object?> get props => [card];
}

class OnlineGivePunishment extends OnlineEvent {
  final PlayingCard card;
  const OnlineGivePunishment(this.card);
  @override
  List<Object?> get props => [card];
}

class OnlineStartNextRound extends OnlineEvent {}

class OnlineDistributeNewCards extends OnlineEvent {}

class OnlineLeaveRoom extends OnlineEvent {}

class OnlineRestartRoom extends OnlineEvent {}

/// Internal: fired when the RTDB gameState stream emits
class RemoteGameStateUpdated extends OnlineEvent {
  final Map<Object?, Object?> data;
  const RemoteGameStateUpdated(this.data);
  @override
  List<Object?> get props => [data];
}

/// Internal: fired when a guest submits a pendingAction (host processes it)
class PendingActionReceived extends OnlineEvent {
  final Map<Object?, Object?> data;
  const PendingActionReceived(this.data);
  @override
  List<Object?> get props => [data];
}

/// Internal: fired when RTDB players stream changes
class PlayersUpdated extends OnlineEvent {
  final List<OnlinePlayerModel> players;
  const PlayersUpdated(this.players);
  @override
  List<Object?> get props => [players];
}

/// Internal: fired when room status changes
class RoomStatusChanged extends OnlineEvent {
  final String status;
  const RoomStatusChanged(this.status);
  @override
  List<Object?> get props => [status];
}

/// Internal: fired when my hand stream updates (guests)
class MyHandUpdated extends OnlineEvent {
  final List<PlayingCard> cards;
  const MyHandUpdated(this.cards);
  @override
  List<Object?> get props => [cards];
}

class RejoinExistingRoom extends OnlineEvent {
  final String roomId;
  final String playerName;
  final String uid;
  const RejoinExistingRoom({required this.roomId, required this.playerName, required this.uid});
  @override
  List<Object?> get props => [roomId, playerName, uid];
}

class DisconnectDataUpdated extends OnlineEvent {
  final Map<Object?, Object?>? data;
  const DisconnectDataUpdated(this.data);
  @override
  List<Object?> get props => [data];
}

