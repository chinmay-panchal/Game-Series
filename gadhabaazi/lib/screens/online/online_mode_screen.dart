import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/online/online_bloc.dart';
import '../../blocs/online/online_event.dart';
import '../../blocs/online/online_state.dart';
import '../../widgets/animated_background.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/premium_toast.dart';
import '../../services/audio_service.dart';
import 'waiting_room_screen.dart';

/// Choose between Create Room and Join Room.
class OnlineModeScreen extends StatefulWidget {
  const OnlineModeScreen({super.key});

  @override
  State<OnlineModeScreen> createState() => _OnlineModeScreenState();
}

class _OnlineModeScreenState extends State<OnlineModeScreen> {
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    return BlocListener<OnlineBloc, OnlineState>(
      listener: (context, state) {
        if (state is OnlineError) {
          PremiumToast.show(context, state.message, isError: true);
        } else if (state is OnlineWaiting && !_navigating) {
          _navigating = true;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WaitingRoomScreen()),
          );
        }
      },
      child: Scaffold(
        body: AnimatedBackground(
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 32),
                const Spacer(),
                Image.asset('assets/images/starting.png', height: 240),
                const SizedBox(height: 20),
                _OnlineOptionCard(
                  assetPath: 'assets/images/create_room.png',
                  onTap: () => _showCreateDialog(context),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.topCenter,
                  heightFactor: 0.5,
                  child: Transform.translate(
                    offset: const Offset(0, -120),
                    child: _OnlineOptionCard(
                      assetPath: 'assets/images/join_room.png',
                      onTap: () => _showJoinDialog(context),
                    ),
                  ),
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

  void _showCreateDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    int maxPlayers = 4;
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
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2C1A), // Wood brown
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: const Border(top: BorderSide(color: Color(0xFFD3AC47), width: 2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create a Room',
                  style: TextStyle(
                    color: Color(0xFFF2D87B),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: const Color(0xFFC2C8A4)),
                  decoration: _inputDecoration('Your Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 20),
                Text(
                  'Max Players: $maxPlayers',
                  style: const TextStyle(color: const Color(0xFFC2C8A4), fontSize: 15),
                ),
                Slider(
                  value: maxPlayers.toDouble(),
                  min: 2,
                  max: 26,
                  divisions: 24,
                  activeColor: const Color(0xFFE3B13C),
                  inactiveColor: const Color(0x3DC2C8A4),
                  label: '$maxPlayers',
                  onChanged: (v) => setModalState(() => maxPlayers = v.toInt()),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;
                      Navigator.pop(ctx);
                      context.read<OnlineBloc>().add(
                        CreateRoom(hostName: name, maxPlayers: maxPlayers),
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
                      'Create',
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

  void _showJoinDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2C1A), // Wood brown
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: const Border(top: BorderSide(color: Color(0xFFD3AC47), width: 2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Join a Room',
              style: TextStyle(
                color: Color(0xFFF2D87B),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: const Color(0xFFC2C8A4)),
              decoration: _inputDecoration('Your Name'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              style: const TextStyle(
                color: const Color(0xFFC2C8A4),
                letterSpacing: 6,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              decoration: _inputDecoration('Room Code (e.g. AB3X7K)'),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  final code = codeCtrl.text.trim().toUpperCase();
                  if (name.isEmpty || code.length < 6) return;
                  Navigator.pop(ctx);
                  context.read<OnlineBloc>().add(
                    JoinRoom(roomCode: code, playerName: name),
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
                  'Join',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: const Color(0x99C2C8A4)),
      filled: true,
      fillColor: const Color(0x1AC2C8A4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.goldAccent, width: 1.5),
      ),
    );
  }
}

class _OnlineOptionCard extends StatefulWidget {
  final String assetPath;
  final VoidCallback onTap;

  const _OnlineOptionCard({
    required this.assetPath,
    required this.onTap,
  });

  @override
  State<_OnlineOptionCard> createState() => _OnlineOptionCardState();
}

class _OnlineOptionCardState extends State<_OnlineOptionCard> {
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
          height: 220,
          width: MediaQuery.of(context).size.width * 0.85,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
