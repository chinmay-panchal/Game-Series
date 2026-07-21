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
                if (_selectedCard != null)
                  ElevatedButton(
                    onPressed: () {
                      context.read<GameBloc>().add(GivePunishmentCard(_selectedCard!));
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.redCard),
                    child: const Text("Confirm Punishment", style: TextStyle(color: AppColors.white)),
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
