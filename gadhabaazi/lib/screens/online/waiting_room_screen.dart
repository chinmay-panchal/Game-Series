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

class WaitingRoomScreen extends StatelessWidget {
  const WaitingRoomScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnlineBloc, OnlineState>(
      listener: (context, state) {
        if (state is OnlineError) {
          PremiumToast.show(context, state.message, isError: true);
        } else if (state is OnlinePlayerTurn ||
            state is OnlineWaitingForTurn ||
            state is OnlineRoundCompleted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const OnlineGameScreen()),
          );
        } else if (state is OnlineInitial) {
          Navigator.of(context).pop();
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
        final players = state.players;
        final isHost = state.isHost;

        return WillPopScope(
          onWillPop: () async {
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
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () {
                                context.read<OnlineBloc>().add(OnlineLeaveRoom());
                                Navigator.of(context).pop();
                              },
                            ),
                            const Spacer(),
                            Text(
                              isHost ? 'Hosting' : 'Waiting',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
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
                            const Text('Room Code',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 13)),
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
                                      color: Colors.white54),
                                  onPressed: () {
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
                        '${players.length}/${room.maxPlayers} players joined',
                        style:
                            const TextStyle(color: Colors.white54, fontSize: 14),
                      ),
                      const SizedBox(height: 32),

                      // Player list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: players.length,
                          itemBuilder: (ctx, i) {
                            final p = players[i];
                            final isFirstPlayer = i == 0;
                            return _PlayerTile(
                              name: p.name,
                              isHost: isFirstPlayer,
                              isOnline: p.isOnline,
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24),
                      if (isHost) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: players.length >= 2
                                  ? () => context
                                      .read<OnlineBloc>()
                                      .add(HostStartGame())
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.goldAccent,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor: Colors.white12,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 18),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                textStyle: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold),
                              ),
                              child: Text(players.length >= 2
                                  ? '▶  Start Game'
                                  : 'Waiting for players...'),
                            ),
                          ),
                        ),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Waiting for the host to start the game…',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
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
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOnline
              ? Colors.white12
              : Colors.redAccent.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isHost
                ? AppColors.goldAccent.withOpacity(0.2)
                : Colors.white12,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: isHost ? AppColors.goldAccent : Colors.white70,
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
                        color: Colors.white,
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
