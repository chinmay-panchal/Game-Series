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
import '../../services/audio_service.dart';

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
    
    // Play ending sound
    AudioService().playEndingBgm();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _onExit() {
    AudioService().stopBgm();
    AudioService().playTapSound();
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
                  // Wooden Name Plate with ending.png
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/images/ending.png',
                        width: MediaQuery.of(context).size.width * 0.9,
                        fit: BoxFit.contain,
                      ),
                      // Position the name over the wooden plank area (lower 22% of the image)
                      Positioned.fill(
                        child: FractionallySizedBox(
                          alignment: Alignment.bottomCenter,
                          heightFactor: 0.22,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  widget.donkeyName.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFFACC15),
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'serif',
                                    letterSpacing: 3,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black87,
                                        blurRadius: 4,
                                        offset: Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 60),
                  ElevatedButton(
                    onPressed: () {
                      _onExit();
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
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      backgroundColor: const Color(0xFFC2C8A4),
                      foregroundColor: const Color(0xFF2C1A0E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(AppStrings.playAgain, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  if (widget.isOnlineRoom) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.replay_rounded),
                      label: const Text('Replay in Same Room', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3A6FF7),
                        foregroundColor: const Color(0xFFC2C8A4),
                        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () {
                        _onExit();
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
