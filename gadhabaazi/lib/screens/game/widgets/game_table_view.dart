import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../blocs/game/game_bloc.dart';
import '../../../blocs/game/game_event.dart';
import '../../../blocs/game/game_state.dart';
import '../../../models/card_model.dart';
import '../../../widgets/animated_background.dart';
import '../../../widgets/table_center_widget.dart';
import 'dealing_animation_widget.dart';
import '../../../widgets/categorized_hand_widget.dart';
import '../../../widgets/suit_indicator_widget.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/audio_service.dart';

class GameTableView extends StatefulWidget {
  final GameBlocState state;

  const GameTableView({super.key, required this.state});

  @override
  State<GameTableView> createState() => _GameTableViewState();
}

class _GameTableViewState extends State<GameTableView> {
  PlayingCard? _selectedCard;

  @override
  void didUpdateWidget(covariant GameTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset selection if turn changes
    if (widget.state != oldWidget.state) {
      _selectedCard = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(child: SizedBox.expand()),
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  _buildHeader(state),
                  const Spacer(),
                  _buildTableCenter(state),
                  const Spacer(),
                  _buildBottomArea(state, context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(GameBlocState state) {
    if (state is GameRoundCompleted) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          "Round complete! ${state.nextRoundLeaderName} leads next.",
          style: const TextStyle(
            color: AppColors.goldAccent,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (state is GamePlayerTurn) {
      return Column(
        children: [
          const SizedBox(height: 16),


          SuitIndicatorWidget(suit: state.currentSuit),

          if (state.isFirstTurn && !state.isHandRevealed) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFC2C8A4),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                ],
              ),
              child: Text(
                "${state.activePlayer.name} starts first with the Ace of Spades ♠",
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTableCenter(GameBlocState state) {
    if (state is GameDealing) {
      return DealingAnimationWidget(
        onComplete: () {
          context.read<GameBloc>().add(DealingAnimationCompleted());
        },
      );
    }
    if (state is GamePlayerTurn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.unendingLoopDetected && state.isHandRevealed) ...[
            ElevatedButton.icon(
              onPressed: () {
                AudioService().playTapSound();
                context.read<GameBloc>().add(DistributeNewCards());
              },
              icon: const Icon(Icons.refresh),
              label: const Text("Distribute New Cards"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.redCard,
                foregroundColor: const Color(0xFFC2C8A4),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TableCenterWidget(
            currentRound: state.currentRound,
            highestCard: state.highestCard,
            playerNames: state.playerNames,
          ),
        ],
      );
    }
    if (state is GameRoundCompleted) {
      return TableCenterWidget(
        currentRound: state.completedRound,
        highestCard: null,
        playerNames: state.playerNames,
      );
    }
    return const SizedBox(height: 250);
  }

  Widget _buildBottomArea(GameBlocState state, BuildContext context) {
    if (state is GameRoundCompleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 32.0),
        child: ElevatedButton(
          onPressed: () {
            AudioService().playTapSound();
            context.read<GameBloc>().add(StartNextRound());
          },
          child: const Text("Next Round"),
        ),
      );
    }

    if (state is GamePlayerTurn) {
      if (!state.isHandRevealed) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 64.0),
          child: ElevatedButton.icon(
            onPressed: () {
              AudioService().playTapSound();
              context.read<GameBloc>().add(RevealHand());
            },
            icon: const Icon(Icons.swap_horiz, color: Color(0xFFF2D87B)),
            label: Text("Pass to ${state.activePlayer.name}"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A2C1A),
              foregroundColor: const Color(0xFFF2D87B),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              side: const BorderSide(color: Color(0xFFD3AC47), width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        );
      }

      return Column(
        children: [
          if (_selectedCard != null) ...[
            Builder(
              builder: (context) {
                final mustPunish =
                    state.currentSuit != null &&
                    !state.activePlayer.hand.any(
                      (c) => c.suit == state.currentSuit,
                    );

                if (mustPunish) {
                  // Player has no card of current suit — selected card IS the punishment card
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2C1A),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                          ],
                          border: Border.all(color: Colors.redAccent, width: 2),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                            SizedBox(width: 8),
                            Text(
                              "No matching suit\nThis card will be given as punishment",
                              style: TextStyle(
                                color: Color(0xFFF2D87B),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () {
                          AudioService().playTapSound();
                          context.read<GameBloc>().add(
                            GivePunishmentCard(_selectedCard!),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade900,
                          foregroundColor: const Color(0xFFC2C8A4),
                          side: const BorderSide(color: Colors.redAccent, width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Give Punishment Card"),
                      ),
                    ],
                  );
                } else {
                  return ElevatedButton(
                    onPressed: () {
                      AudioService().playTapSound();
                      context.read<GameBloc>().add(PlayCard(_selectedCard!));
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A2C1A),
                      foregroundColor: const Color(0xFFF2D87B),
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      side: const BorderSide(color: Color(0xFFD3AC47), width: 2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Play Card"),
                  );
                }
              },
            ),
          ] else
            const SizedBox(height: 48),
          const SizedBox(height: 16),
          CategorizedHandWidget(
            key: ValueKey(
              '${state.activePlayer.id}_${state.currentRound?.roundNumber ?? 0}',
            ),
            cards: state.activePlayer.hand,
            selectedCard: _selectedCard,
            isCardEnabled: (_) => true,
            onCardTap: (card) {
              setState(() {
                _selectedCard = _selectedCard == card ? null : card;
              });
            },
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}
