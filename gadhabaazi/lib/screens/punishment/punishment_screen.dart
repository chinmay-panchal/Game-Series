import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../blocs/game/game_state.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/categorized_hand_widget.dart';
import '../../models/card_model.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';

class PunishmentScreen extends StatefulWidget {
  final GamePunishmentSelection state;

  const PunishmentScreen({super.key, required this.state});

  @override
  State<PunishmentScreen> createState() => _PunishmentScreenState();
}

class _PunishmentScreenState extends State<PunishmentScreen> {
  PlayingCard? _selectedCard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(child: SizedBox.expand()),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),
                Text(
                  AppStrings.selectPunishment,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.redCard,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Give to ${widget.state.receivingPlayerName}",
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 16),
                ),
                const Spacer(),
                Builder(
                  builder: (context) {
                    final hand = widget.state.givingPlayer.hand;
                    final uniqueSuits = hand.map((c) => c.suit).toSet();
                    final canPunishWholeSuit = uniqueSuits.length == 1;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canPunishWholeSuit) ...[
                          ElevatedButton.icon(
                            onPressed: () {
                              context.read<GameBloc>().add(const GiveWholeSuitPunishment());
                            },
                            icon: const Icon(Icons.bolt, color: Color(0xFF2C1A0E)),
                            label: Text(
                              hand.length > 1
                                  ? "Punish Whole Suite (${hand.length} Cards)"
                                  : "Punish Whole Suite",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF2C1A0E),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFE3B13C),
                              foregroundColor: const Color(0xFF2C1A0E),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              side: const BorderSide(color: Color(0xFFF2D87B), width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 4,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        if (_selectedCard != null)
                          ElevatedButton(
                            onPressed: () {
                              context.read<GameBloc>().add(GivePunishmentCard(_selectedCard!));
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red.shade900,
                              foregroundColor: const Color(0xFFC2C8A4),
                              side: const BorderSide(color: Colors.redAccent, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              canPunishWholeSuit
                                  ? "Punish with This Card Only"
                                  : "Confirm Punishment",
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),
                CategorizedHandWidget(
                  cards: widget.state.givingPlayer.hand,
                  selectedCard: _selectedCard,
                  isCardEnabled: (_) => true,
                  onCardTap: (card) {
                    setState(() {
                      _selectedCard = _selectedCard == card ? null : card;
                    });
                  },
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
