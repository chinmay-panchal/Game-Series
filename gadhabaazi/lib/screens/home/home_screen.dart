import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../widgets/animated_background.dart';
import '../../core/constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/game_screen.dart';
import '../online/online_mode_screen.dart';

import 'dart:async';
import '../../blocs/online/online_bloc.dart';
import '../../blocs/online/online_event.dart';
import '../online/online_game_screen.dart';
import '../../services/audio_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _isLoading = true;

  String? _rejoinRoomId;
  String? _rejoinPlayerName;
  String? _rejoinPlayerUid;
  int _rejoinSecondsRemaining = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSavedGame();
    _checkActiveRoomWithRetry();
  }

  Future<void> _checkActiveRoomWithRetry() async {
    final prefs = await SharedPreferences.getInstance();
    String? roomId = prefs.getString('active_online_room_id');
    if (roomId != null) {
      await _checkActiveOnlineRoom();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    roomId = prefs.getString('active_online_room_id');
    if (roomId != null) {
      await _checkActiveOnlineRoom();
      return;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkActiveOnlineRoom(autoRejoinIfValid: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkSavedGame() async {
    // Left empty for future offline game loading logic
  }

  Future<void> _checkActiveOnlineRoom({bool autoRejoinIfValid = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final roomId = prefs.getString('active_online_room_id');
      final roomCode = prefs.getString('active_online_room_code');
      final playerName = prefs.getString('active_online_player_name');
      final playerUid = prefs.getString('active_online_player_uid');

      print(
        'RJDBG 1: roomId=$roomId roomCode=$roomCode playerName=$playerName playerUid=$playerUid',
      );

      if (roomId == null || roomCode == null || playerName == null || playerUid == null) {
        print('RJDBG 2: bailing — one of roomId/roomCode/playerName/playerUid is null');
        if (mounted) setState(() {
          _rejoinRoomId = null;
          _isLoading = false;
        });
        return;
      }
      if (!mounted) {
        print('RJDBG 3: bailing — widget not mounted');
        return;
      }
      final repository = context.read<OnlineBloc>().repository;

      final room = await repository.getActiveRoom(roomId);
      print(
        'RJDBG 4: getActiveRoom() -> status=${room?.status}, room==null: ${room == null}',
      );

      if (room == null ||
          (room.status != 'waiting' && room.status != 'in_progress')) {
        print('RJDBG 5: bailing — room null or status not waiting/in_progress');
        if (mounted) {
          setState(() {
            _rejoinRoomId = null;
            _isLoading = false;
          });
          _clearSavedOnlineSession();
        }
        return;
      }

      final disconnectData = await repository.getDisconnectData(roomId);
      print('RJDBG 6: getDisconnectData() -> $disconnectData');
      final now = DateTime.now().millisecondsSinceEpoch;

      int secondsRemaining = 30;
      if (disconnectData != null) {
        final expiresAt = disconnectData['expiresAt'] as int? ?? 0;
        await prefs.setInt('active_online_expires_at', expiresAt);
        secondsRemaining = ((expiresAt - now) / 1000).ceil();
        print(
          'RJDBG 7: from RTDB, expiresAt=$expiresAt now=$now secondsRemaining=$secondsRemaining',
        );
      } else {
        final expiresAt = prefs.getInt('active_online_expires_at');
        if (expiresAt != null) {
          secondsRemaining = ((expiresAt - now) / 1000).ceil();
        }
        print(
          'RJDBG 8: no RTDB disconnectData, local expiresAt=$expiresAt secondsRemaining=$secondsRemaining',
        );
      }

      if (secondsRemaining <= 0) {
        print('RJDBG 9: bailing — secondsRemaining <= 0');
        if (mounted) {
          setState(() {
            _rejoinRoomId = null;
            _isLoading = false;
          });
          _clearSavedOnlineSession();
        }
        return;
      }

      print(
        'RJDBG 10: SUCCESS — setting rejoin state, roomId=$roomId secondsRemaining=$secondsRemaining',
      );
      if (mounted) {
        setState(() {
          _rejoinRoomId = roomId;
          _rejoinPlayerName = playerName;
          _rejoinPlayerUid = playerUid;
          _rejoinSecondsRemaining = secondsRemaining;
          _isLoading = false;
        });
        _startCountdownTimer();

        if (autoRejoinIfValid) {
          _executeRejoin();
        }
      }
    } catch (e, st) {
      print('RJDBG ERROR: $e');
      print('RJDBG STACK: $st');
    }
  }

  void _executeRejoin() async {
    if (_rejoinRoomId == null || _rejoinPlayerUid == null) return;
    AudioService().stopBgm();
    _countdownTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('active_online_expires_at');
    if (mounted) {
      context.read<OnlineBloc>().add(
        RejoinExistingRoom(
          roomId: _rejoinRoomId!,
          playerName: _rejoinPlayerName ?? 'Player',
          uid: _rejoinPlayerUid!,
        ),
      );
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => const OnlineGameScreen(isRejoin: true),
            ),
          )
          .then((_) => _checkActiveOnlineRoom());
    }
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
          _rejoinRoomId = null;
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
    await prefs.remove('active_online_expires_at');
  }

  void _showPlayerCountDialog(BuildContext context) {
    int playerCount = 2;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 32,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2C1A), // Wood brown
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: const Border(
                top: BorderSide(color: Color(0xFFD3AC47), width: 2),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How many players? 🃏',
                  style: TextStyle(
                    color: Color(0xFFF2D87B),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cards will be distributed to $playerCount players',
                  style: const TextStyle(
                    color: const Color(0xFFC2C8A4),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                Slider(
                  value: playerCount.toDouble(),
                  min: 2,
                  max: 6,
                  divisions: 4,
                  activeColor: const Color(0xFFE3B13C),
                  inactiveColor: const Color(0x3DC2C8A4),
                  label: '$playerCount',
                  onChanged: (v) =>
                      setModalState(() => playerCount = v.toInt()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      AudioService().playTapSound();
                      Navigator.pop(ctx);
                      AudioService().stopBgm();
                      final names = List.generate(
                        playerCount,
                        (i) => 'Player ${i + 1}',
                      );
                      context.read<GameBloc>().add(
                        StartGame(playerNames: names),
                      );
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const GameScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE3B13C),
                      foregroundColor: const Color(0xFF2C1A0E),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Start Game',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRejoin = _rejoinRoomId != null;
    const double logoHeight = 250;
    const double buttonHeight = 220;

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.goldAccent,
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          // App title logo
                          Image.asset(
                            'assets/images/starting.png',
                            height: logoHeight,
                          ),
                          const SizedBox(height: 10),

                          // ─── PLAY ONLINE / REJOIN ──────────────────────────
                          ImageButton(
                            assetPath: hasRejoin
                                ? 'assets/images/rejoin_online_game.png'
                                : 'assets/images/play_online.png',
                            height: buttonHeight,
                            width: MediaQuery.of(context).size.width * 0.85,
                            onTap: hasRejoin
                                ? () {
                                    AudioService().playTapSound();
                                    _executeRejoin();
                                  }
                                : () {
                                    AudioService().playTapSound();
                                    Navigator.of(context)
                                        .push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const OnlineModeScreen(),
                                          ),
                                        )
                                        .then((_) => _checkActiveOnlineRoom());
                                  },
                          ),
                          const SizedBox(height: 6),
                          // ─── PLAY OFFLINE ──────────────────────────────────
                          Align(
                            alignment: Alignment.topCenter,
                            heightFactor: 0.5,
                            child: Transform.translate(
                              offset: const Offset(0, -120),
                              child: ImageButton(
                                assetPath: 'assets/images/play_offline.png',
                                height: buttonHeight,
                                width: MediaQuery.of(context).size.width * 0.85,
                                onTap: () {
                                  AudioService().playTapSound();
                                  _showPlayerCountDialog(context);
                                },
                              ),
                            ),
                          ),

                          const Spacer(),
                        ],
                      ),
              ),
              if (hasRejoin)
                Positioned(
                  top: 16,
                  right: 16,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFD3AC47),
                            width: 2,
                          ),
                          color: const Color(0xFF1A2C1A).withOpacity(0.85),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$_rejoinSecondsRemaining',
                          style: const TextStyle(
                            color: Color(0xFFF2D87B),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          _countdownTimer?.cancel();
                          setState(() {
                            _rejoinSecondsRemaining = 0;
                            _rejoinRoomId = null;
                          });
                          _clearSavedOnlineSession();
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.redAccent.withOpacity(0.85),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
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
