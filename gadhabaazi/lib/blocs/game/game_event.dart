import 'package:equatable/equatable.dart';
import '../../models/card_model.dart';

abstract class GameEvent extends Equatable {
  const GameEvent();

  @override
  List<Object?> get props => [];
}

class StartGame extends GameEvent {
  final List<String> playerNames;

  const StartGame({required this.playerNames});

  @override
  List<Object?> get props => [playerNames];
}

class LoadGame extends GameEvent {
  final String jsonState;
  const LoadGame({required this.jsonState});

  @override
  List<Object?> get props => [jsonState];
}

class RevealHand extends GameEvent {}

class DealingAnimationCompleted extends GameEvent {}

class PlayCard extends GameEvent {
  final PlayingCard card;
  const PlayCard(this.card);

  @override
  List<Object?> get props => [card];
}

class GivePunishmentCard extends GameEvent {
  final PlayingCard card;
  const GivePunishmentCard(this.card);

  @override
  List<Object?> get props => [card];
}

class StartNextRound extends GameEvent {}

class RestartGame extends GameEvent {}
