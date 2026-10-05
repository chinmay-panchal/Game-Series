import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/online/online_bloc.dart';
import '../../blocs/online/online_event.dart';
import '../../blocs/online/online_state.dart';
import '../../widgets/animated_background.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/premium_toast.dart';
import 'online_game_screen.dart';
import '../home/home_screen.dart';
import '../../services/audio_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key});

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    context.read<OnlineBloc>().add(OnlineReassertPresence());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<OnlineBloc>().add(OnlineReassertPresence());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnlineBloc, OnlineState>(
      listener: (context, state) {
        if (state is OnlineError) {
          PremiumToast.show(context, state.message, isError: true);
        } else if (state is OnlinePlayerTurn ||
            state is OnlineWaitingForTurn ||
            state is OnlineRoundCompleted) {
          AudioService().stopBgm();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OnlineGameScreen()),
          );
        } else if (state is OnlineInitial) {
          // Use pushAndRemoveUntil in case there's no route to pop back to
          // (e.g. when arriving here via "Replay in Same Room" which clears the stack)
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
          );
        }
      },
      builder: (context, state) {
        if (state is! OnlineWaiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0D0D1A),
            body: Center(child: CircularProgressIndicator(color: AppColors.goldAccent)),
          );
        }

        final room = state.room;
        // In the lobby, only active online players are shown (offline players are removed so slots are freed)
        final activePlayers = state.players.where((p) => p.isOnline).toList();
        final isHost = state.isHost;
        final canStart = activePlayers.length >= 2;

        String startButtonText;
        if (activePlayers.length < 2) {
          startButtonText = 'Waiting for players...';
        } else {
          startButtonText = '▶  Start Game';
        }

        return WillPopScope(
          onWillPop: () async {
            // Eagerly clear session in prefs so HomeScreen doesn't see a stale rejoin room
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('active_online_room_id');
            await prefs.remove('active_online_room_code');
            await prefs.remove('active_online_player_name');
            await prefs.remove('active_online_player_uid');
            await prefs.remove('active_online_expires_at');
            context.read<OnlineBloc>().add(OnlineLeaveRoom());
            return true;
          },
          child: Scaffold(
            body: AnimatedBackground(
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFFC2C8A4)),
                              onPressed: () async {
                                AudioService().playTapSound();
                                final prefs = await SharedPreferences.getInstance();
                                await prefs.remove('active_online_room_id');
                                await prefs.remove('active_online_room_code');
                                await prefs.remove('active_online_player_name');
                                await prefs.remove('active_online_player_uid');
                                await prefs.remove('active_online_expires_at');
                                context.read<OnlineBloc>().add(OnlineLeaveRoom());
                                Navigator.of(context).pop();
                              },
                            ),
                            const Spacer(),
                            Text(
                              isHost ? '👑 Hosting' : '⏳ Waiting',
                              style: const TextStyle(
                                  color: Color(0xFFF2D87B), fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Room code badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.goldAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.goldAccent.withOpacity(0.4)),
                        ),
                        child: Column(
                          children: [
                            const Text('ROOM CODE',
                                style: TextStyle(
                                    color: Color(0xFFF2D87B), fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  room.roomCode,
                                  style: const TextStyle(
                                    color: AppColors.goldAccent,
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 8,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(Icons.copy,
                                      color: Color(0xFFD3AC47)),
                                  onPressed: () {
                                    AudioService().playTapSound();
                                    Clipboard.setData(
                                        ClipboardData(text: room.roomCode));
                                    PremiumToast.show(
                                        context, 'Code copied to clipboard!');
                                  },
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '${activePlayers.length}/${room.maxPlayers} players joined',
                        style: const TextStyle(color: Color(0xFFF2D87B), fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 32),

                      // Player list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: activePlayers.length,
                          itemBuilder: (ctx, i) {
                            final p = activePlayers[i];
                            final isPlayerHost = room.hostId.isNotEmpty
                                ? p.uid == room.hostId
                                : (isHost && i == 0);
                            return _PlayerTile(
                              name: p.name,
                              isHost: isPlayerHost,
                              isOnline: true,
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isHost)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: canStart
                                      ? () {
                                          AudioService().playTapSound();
                                          context
                                              .read<OnlineBloc>()
                                              .add(HostStartGame());
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.goldAccent,
                                    foregroundColor: const Color(0xFF2C1A0E),
                                    disabledBackgroundColor:
                                        const Color(0x1FC2C8A4),
                                    disabledForegroundColor:
                                        const Color(0x80C2C8A4),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 18),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    textStyle: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  child: Text(startButtonText),
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 18, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: const Color(0x1FC2C8A4),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0x33C2C8A4),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFF2D87B),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        'Waiting for the host to start the game…',
                                        style: TextStyle(
                                          color: Color(0xFFC2C8A4),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlayerTile extends StatelessWidget {
  final String name;
  final bool isHost;
  final bool isOnline;

  const _PlayerTile({
    required this.name,
    required this.isHost,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2C1A).withOpacity(0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOnline
              ? const Color(0xFFD3AC47).withOpacity(0.4)
              : Colors.redAccent.withOpacity(0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isHost
                ? AppColors.goldAccent.withOpacity(0.2)
                : const Color(0x1FC2C8A4),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: isHost ? AppColors.goldAccent : const Color(0xFFC2C8A4),
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        color: const Color(0xFFC2C8A4),
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
                if (isHost)
                  const Text('Host',
                      style:
                          TextStyle(color: AppColors.goldAccent, fontSize: 12)),
              ],
            ),
          ),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.greenAccent : Colors.redAccent,
              boxShadow: [
                BoxShadow(
                  color: (isOnline ? Colors.greenAccent : Colors.redAccent)
                      .withOpacity(0.5),
                  blurRadius: 6,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
