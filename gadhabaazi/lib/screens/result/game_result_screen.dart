import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:confetti/confetti.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../blocs/online/online_bloc.dart';
import '../../blocs/online/online_event.dart';
import '../../blocs/online/online_state.dart';
import '../../widgets/animated_background.dart';
import 'package:google_fonts/google_fonts.dart';
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
    _clearOnlineSession();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    _confettiController.play();

    // Play ending sound
    AudioService().playEndingBgm();
  }

  Future<void> _clearOnlineSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('active_online_room_id');
      await prefs.remove('active_online_room_code');
      await prefs.remove('active_online_player_name');
      await prefs.remove('active_online_player_uid');
      await prefs.remove('active_online_expires_at');
    } catch (_) {}
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
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(child: SizedBox.expand()),
          SafeArea(
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              // CHUNK 3: Center + mainAxisSize.min gives true vertical
              // centering of the whole content block, regardless of
              // SafeArea insets. If content is ever too tall for very
              // small screens, this will overflow — swap back to the
              // SingleChildScrollView version if that becomes an issue.
              child: Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/loser.png',
                        width: size.width * 0.75,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "${widget.donkeyName} is the donkey",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cinzel(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFF2D87B),
                            shadows: const [
                              Shadow(
                                color: Colors.black87,
                                blurRadius: 10,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 24,
                      ), // gap between text and buttons
                      ImageButton(
                        assetPath: 'assets/images/go_home.png',
                        height: 220,
                        width: size.width * 0.85,
                        onTap: () {
                          _onExit();
                          context.read<GameBloc>().add(RestartGame());
                          final onlineBloc = context.read<OnlineBloc>();
                          if (onlineBloc.state is! OnlineInitial) {
                            onlineBloc.add(OnlineLeaveRoom());
                          }
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const HomeScreen(),
                            ),
                            (route) => false,
                          );
                        },
                      ),
                      if (widget.isOnlineRoom)
                        Transform.translate(
                          offset: const Offset(0, -50),
                          child: ImageButton(
                            assetPath: 'assets/images/replay.png',
                            height: 220,
                            width: size.width * 0.85,
                            onTap: () {
                              _onExit();
                              context.read<OnlineBloc>().add(
                                OnlineRestartRoom(),
                              );
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const WaitingRoomScreen(),
                                ),
                                (route) => false,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
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

class ImageButton extends StatefulWidget {
  final String assetPath;
  final VoidCallback onTap;
  final double height;
  final double? width;

  const ImageButton({
    super.key,
    required this.assetPath,
    required this.onTap,
    this.height = 70.0,
    this.width,
  });

  @override
  State<ImageButton> createState() => _ImageButtonState();
}

class _ImageButtonState extends State<ImageButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        AudioService().playTapSound();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: Image.asset(
          widget.assetPath,
          height: widget.height,
          width: widget.width,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
