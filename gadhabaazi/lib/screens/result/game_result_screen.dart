import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:confetti/confetti.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../blocs/online/online_bloc.dart';
import '../../blocs/online/online_event.dart';
import '../../blocs/online/online_state.dart';
import '../../widgets/animated_background.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../home/home_screen.dart';
import '../online/waiting_room_screen.dart';
import '../../engine/history/move_history.dart';

class GameResultScreen extends StatefulWidget {
  final String donkeyName;
  final List<String> finishingOrder;
  final MoveHistory history;
  final bool isOnlineRoom;

  const GameResultScreen({
    super.key,
    required this.donkeyName,
    required this.finishingOrder,
    required this.history,
    this.isOnlineRoom = false,
  });

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(child: SizedBox.expand()),
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/donkey_gif.jpg',
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Donkey",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.goldAccent,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.donkeyName,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      color: AppColors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),
                  const Text(
                    "Finishing Order:",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ...widget.finishingOrder.asMap().entries.map((entry) {
                    int rank = entry.key + 1;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        "$rank. ${entry.value}",
                        style: TextStyle(
                          color: rank == widget.finishingOrder.length ? AppColors.redCard : AppColors.white,
                          fontSize: 20,
                          fontWeight: rank == 1 ? FontWeight.bold : FontWeight.normal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }),
                  const SizedBox(height: 60),
                  ElevatedButton(
                    onPressed: () {
                      context.read<GameBloc>().add(RestartGame());
                      // If it's an online game, also dispatch leave room
                      final onlineBloc = context.read<OnlineBloc>();
                      if (onlineBloc.state is! OnlineInitial) {
                        onlineBloc.add(OnlineLeaveRoom());
                      }
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => false,
                      );
                    },
                    child: const Text(AppStrings.playAgain),
                  ),
                  if (widget.isOnlineRoom) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Replay in Same Room'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3A6FF7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        context.read<OnlineBloc>().add(OnlineRestartRoom());
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const WaitingRoomScreen()),
                          (route) => false,
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: 3.14159 / 2, // Down
              maxBlastForce: 5,
              minBlastForce: 2,
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              gravity: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}
