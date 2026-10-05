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

class OnlineReassertPresence extends OnlineEvent {}

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

/// Internal: fired when room meta changes (e.g. hostId, status)
class RoomMetaChanged extends OnlineEvent {
  final Map<Object?, Object?> meta;
  const RoomMetaChanged(this.meta);
  @override
  List<Object?> get props => [meta];
}

/// Internal: fired when my hand stream updates (guests)
class MyHandUpdated extends OnlineEvent {
  final List<PlayingCard> cards;
  const MyHandUpdated(this.cards);
  @override
  List<Object?> get props => [cards];
}

/// Internal: fired (host only) when an online player goes offline — triggers card redistribution
class OnlinePlayerLeft extends OnlineEvent {
  final String playerUid;
  const OnlinePlayerLeft(this.playerUid);
  @override
  List<Object?> get props => [playerUid];
}
