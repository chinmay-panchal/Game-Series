import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/game/game_bloc.dart';
import '../../blocs/game/game_event.dart';
import '../../widgets/animated_background.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/game_screen.dart';
import '../online/online_mode_screen.dart';
import '../../services/audio_service.dart';
import '../../widgets/rule_book_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _showWalkthrough = false;

  @override
  void initState() {
    super.initState();
    _checkWalkthrough();
  }

  Future<void> _checkWalkthrough() async {
    final prefs = await SharedPreferences.getInstance();
    final bool hasSeen = prefs.getBool('hasSeenWalkthrough') ?? false;
    if (!hasSeen && mounted) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) {
        setState(() => _showWalkthrough = true);
      }
    }
  }

  Future<void> _dismissWalkthrough({bool openRuleBook = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenWalkthrough', true);
    if (mounted) {
      setState(() => _showWalkthrough = false);
      if (openRuleBook) {
        RuleBookSheet.show(context);
      }
    }
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
              color: const Color(0xFF1A2C1A),
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
                    color: Color(0xFFC2C8A4),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double buttonWidth = (screenWidth * 0.85).clamp(240.0, 360.0);
    final double buttonHeight = buttonWidth / 2.5;
    final double logoHeight = (screenHeight * 0.28).clamp(140.0, 220.0);

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SizedBox.expand(
                child: Center(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // App title logo
                        Image.asset(
                          'assets/images/starting.png',
                          height: logoHeight,
                          fit: BoxFit.contain,
                        ),
                        const SizedBox(height: 24),

                        // ─── PLAY ONLINE ───────────────────────────────────
                        ImageButton(
                          assetPath: 'assets/images/play_online.png',
                          height: buttonHeight,
                          width: buttonWidth,
                          onTap: () {
                            AudioService().playTapSound();
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const OnlineModeScreen(),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 20),

                        // ─── PLAY OFFLINE ──────────────────────────────────
                        ImageButton(
                          assetPath: 'assets/images/play_offline.png',
                          height: buttonHeight,
                          width: buttonWidth,
                          onTap: () {
                            AudioService().playTapSound();
                            _showPlayerCountDialog(context);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ─── TOP BAR: RULE BOOK ────────────────────────────────────
              Positioned(
                top: 16,
                left: 16,
                child: _buildRuleBookButton(),
              ),

              // ─── ONE-TIME WALKTHROUGH OVERLAY ─────────────────────────
              if (_showWalkthrough)
                _buildWalkthroughOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRuleBookButton() {
    return GestureDetector(
      onTap: () {
        AudioService().playTapSound();
        RuleBookSheet.show(context);
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1A2C1A).withOpacity(0.9),
          border: Border.all(
            color: const Color(0xFFD3AC47),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.menu_book_rounded,
          color: Color(0xFFF2D87B),
          size: 22,
        ),
      ),
    );
  }

  Widget _buildWalkthroughOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _dismissWalkthrough(),
        child: Container(
          color: Colors.black.withOpacity(0.65),
          child: Stack(
            children: [
              Positioned(
                top: 16,
                left: 16,
                child: GestureDetector(
                  onTap: () => _dismissWalkthrough(openRuleBook: true),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A2C1A),
                      border: Border.all(
                        color: const Color(0xFFF2D87B),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFF2D87B).withOpacity(0.6),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.menu_book_rounded,
                      color: Color(0xFFF2D87B),
                      size: 24,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 72,
                left: 16,
                child: GestureDetector(
                  onTap: () {},
                  child: Container(
                    width: 270,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2C1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFD3AC47),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Text(
                            'Tap here anytime to see how to play',
                            style: TextStyle(
                              color: Color(0xFFF2D87B),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _dismissWalkthrough(),
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.12),
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Color(0xFFC2C8A4),
                              size: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
      behavior: HitTestBehavior.opaque,
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
        scale: _isPressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: Image.asset(
            widget.assetPath,
            height: widget.height,
            width: widget.width,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
