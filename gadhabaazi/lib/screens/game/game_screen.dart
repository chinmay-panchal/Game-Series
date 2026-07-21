import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_state.dart';
import '../home/home_screen.dart';
import '../punishment/punishment_screen.dart';
import '../result/game_result_screen.dart';
import 'widgets/game_table_view.dart';
import '../../core/constants/app_colors.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GameBloc, GameBlocState>(
      listener: (context, state) {
        if (state is GameError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message, style: const TextStyle(color: Colors.white)),
              backgroundColor: AppColors.redCard,
              duration: const Duration(seconds: 2),
            ),
          );
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
          return GameTableView(state: state);
        }
      },
    );
  }
}
