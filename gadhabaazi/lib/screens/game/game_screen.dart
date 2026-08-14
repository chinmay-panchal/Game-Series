import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_state.dart';
import '../home/home_screen.dart';
import '../punishment/punishment_screen.dart';
import '../result/game_result_screen.dart';
import 'widgets/game_table_view.dart';
import '../../widgets/premium_toast.dart';
import '../../core/constants/app_colors.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  String? _lastPlayerName;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
      child: BlocConsumer<GameBloc, GameBlocState>(
        listenWhen: (previous, current) {
          if (current is GameError) return true;
          if (current is GameRoundCompleted) return true;
          if (current is GamePlayerTurn) {
            return _lastPlayerName != current.activePlayer.name;
          }
          return false;
        },
        listener: (context, state) {
          if (state is GameError) {
            PremiumToast.show(context, state.message, isError: true);
          } else if (state is GameRoundCompleted) {
            // Show punishment toast if this round ended with a punishment
            if (state.completedRound.punishmentCard != null) {
              final card = state.completedRound.punishmentCard!;
              PremiumToast.show(
                context,
                '🎴 Punished with ${card.rank.label}${card.suit.symbol}! Check your hand.',
                isError: true,
                duration: const Duration(seconds: 4),
              );
            }
          } else if (state is GamePlayerTurn) {
            _lastPlayerName = state.activePlayer.name;
            PremiumToast.show(context, "${state.activePlayer.name}'s turn");
          }
        },
        builder: (context, state) {
          if (state is GameInitial) {
            return const HomeScreen();
          } else if (state is GamePunishmentSelection) {
            return PunishmentScreen(state: state);
          } else if (state is GameFinished) {
            return GameResultScreen(
              donkeyName: state.donkeyName,
              finishingOrder: state.finishingOrder,
              history: state.history,
            );
          } else {
            // Initialize last player on first build if possible without toast spam
            if (state is GamePlayerTurn && _lastPlayerName == null) {
              _lastPlayerName = state.activePlayer.name;
            }
            return GameTableView(state: state);
          }
        },
      ),
    );
  }
}
