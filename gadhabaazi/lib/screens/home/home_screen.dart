import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../widgets/animated_background.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/game_screen.dart';
import '../online/online_mode_screen.dart';

import 'dart:async';
import 'dart:math';
import '../../blocs/online/online_bloc.dart';
import '../../blocs/online/online_event.dart';
import '../online/online_game_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _savedGameJson;
  bool _isLoading = true;

  // Active online room rejoin session
  String? _rejoinRoomId;
  String? _rejoinPlayerName;
  int _rejoinSecondsRemaining = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSavedGame();
    _checkActiveOnlineRoom();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkActiveOnlineRoom();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSavedGame() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('saved_game');
      setState(() {
        _savedGameJson = saved;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _checkActiveOnlineRoom() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roomId = prefs.getString('active_online_room_id');
      final roomCode = prefs.getString('active_online_room_code');
      final playerName = prefs.getString('active_online_player_name');
      final playerUid = prefs.getString('active_online_player_uid');

      if (roomId != null && roomCode != null && playerName != null) {
        final repository = context.read<OnlineBloc>().repository;
        final room = await repository.getActiveRoom(roomId);

        if (room != null) {
          final uid = playerUid ?? await repository.signInAnonymously();
          final isMember = await repository.isPlayerInRoom(roomId, uid);
          if (isMember) {
            setState(() {
              _rejoinRoomId = roomId;
              _rejoinPlayerName = playerName;
              _rejoinSecondsRemaining = 300; // Always active while room is in_progress/waiting
            });
          } else {
            setState(() => _rejoinRoomId = null);
            _clearSavedOnlineSession();
          }
        } else {
          setState(() => _rejoinRoomId = null);
          _clearSavedOnlineSession();
        }
      } else {
        setState(() => _rejoinRoomId = null);
      }
    } catch (_) {}
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_rejoinSecondsRemaining > 1) {
        setState(() {
          _rejoinSecondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _rejoinSecondsRemaining = 0;
        });
        _clearSavedOnlineSession();
      }
    });
  }

  Future<void> _clearSavedOnlineSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_online_room_id');
    await prefs.remove('active_online_room_code');
    await prefs.remove('active_online_player_name');
    await prefs.remove('active_online_player_uid');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.goldAccent))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(),
                      // App title
                      Text(
                        AppStrings.appTitle,
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              color: AppColors.goldAccent,
                              fontWeight: FontWeight.bold,
                              shadows: const [
                                Shadow(
                                    color: Colors.black54,
                                    offset: Offset(2, 2),
                                    blurRadius: 4),
                              ],
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The classic card game',
                        style: TextStyle(color: Colors.white38, fontSize: 15),
                      ),
                      const Spacer(),

                      // ── Play Offline ──
                      _SectionLabel(label: '📱 PLAY OFFLINE'),
                      const SizedBox(height: 12),
                      if (_savedGameJson != null) ...[
                        _HomeButton(
                          label: '▶  Resume Game',
                          color: AppColors.goldAccent,
                          textColor: Colors.black,
                          onTap: () {
                            context
                                .read<GameBloc>()
                                .add(LoadGame(jsonState: _savedGameJson!));
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const GameScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () {
                            context.read<GameBloc>().add(const StartGame(
                                playerNames: ['Player 1', 'Player 2']));
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const GameScreen()),
                            );
                          },
                          child: const Text('Start New Game',
                              style: TextStyle(color: Colors.white54)),
                        ),
                      ] else ...[
                        _HomeButton(
                          label: AppStrings.newGame,
                          color: Colors.white,
                          textColor: Colors.black87,
                          onTap: () {
                            context.read<GameBloc>().add(const StartGame(
                                playerNames: ['Player 1', 'Player 2']));
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => const GameScreen()),
                            );
                          },
                        ),
                      ],

                      const SizedBox(height: 32),

                      // ── Play Online ──
                      _SectionLabel(label: '🌐 PLAY ONLINE'),
                      const SizedBox(height: 12),

                      if (_rejoinRoomId != null) ...[
                        _HomeButton(
                          label: '🔄 Rejoin Active Game',
                          color: AppColors.goldAccent,
                          textColor: Colors.black,
                          onTap: () {
                            context.read<OnlineBloc>().add(
                              RejoinExistingRoom(
                                roomId: _rejoinRoomId!,
                                playerName: _rejoinPlayerName ?? 'Player',
                              ),
                            );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const OnlineGameScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                      _HomeButton(
                        label: 'Play Online',
                        color: const Color(0xFF3A6FF7),
                        textColor: Colors.white,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const OnlineModeScreen()),
                          ).then((_) => _checkActiveOnlineRoom());
                        },
                      ),

                      const Spacer(),
                      const SizedBox(height: 32),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.white12, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white30,
                    fontSize: 11,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(child: Divider(color: Colors.white12, thickness: 1)),
        ],
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  final VoidCallback onTap;

  const _HomeButton({
    required this.label,
    required this.color,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: textColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 4,
            textStyle:
                const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}


