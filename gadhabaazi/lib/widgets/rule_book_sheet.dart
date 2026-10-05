import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/audio_service.dart';

class RuleBookSheet extends StatelessWidget {
  const RuleBookSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const RuleBookSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final sheetHeight = mediaQuery.size.height * 0.82;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF1A2C1A), // Dark wood/forest green
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFFD3AC47), width: 2),
          left: BorderSide(color: Color(0xFFD3AC47), width: 0.5),
          right: BorderSide(color: Color(0xFFD3AC47), width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD3AC47).withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.menu_book_rounded,
                  color: Color(0xFFF2D87B),
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'How to Play GadhaBaazi',
                    style: GoogleFonts.cinzel(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFFF2D87B),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    AudioService().playTapSound();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.close, color: Color(0xFFC2C8A4)),
                  splashRadius: 20,
                  tooltip: 'Close',
                ),
              ],
            ),
          ),

          const Divider(color: Color(0x3DD3AC47), height: 1),

          // Scrollable Rules Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                // Quick Hint Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F5B30).withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFD3AC47).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Text('🎯', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The Golden Goal: Empty your hand to win! The last player with cards is the Donkey ("Gadha").',
                          style: TextStyle(
                            color: const Color(0xFFF2D87B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            fontFamily: GoogleFonts.inter().fontFamily,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ─── SECTION 1: HOW TO START ───
                _buildSectionHeader(
                  title: '1. How to Start',
                  icon: Icons.play_circle_outline_rounded,
                ),
                const SizedBox(height: 8),
                _buildCard([
                  _buildBullet(
                    title: 'Play Offline',
                    description:
                        'Practice solo anytime against smart bots (2 to 6 players). Perfect for learning the game at your own pace without an internet connection.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'Play Online',
                    description:
                        'Play live multiplayer with friends or family anywhere in real time!',
                  ),
                ]),
                const SizedBox(height: 16),

                // ─── SECTION 2: PLAY ONLINE ROOMS ───
                _buildSectionHeader(
                  title: '2. Online Rooms',
                  icon: Icons.groups_rounded,
                ),
                const SizedBox(height: 8),
                _buildCard([
                  _buildBullet(
                    title: 'Create a Room',
                    description:
                        'One player acts as host, selects the player limit (2 to 26 players, default is 4), and shares the 6-character room code.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'Join with Code',
                    description:
                        'Other players enter their name and the room code to join the lobby.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'Player Cap',
                    description:
                        'Rooms support anywhere from 2 up to 26 players per match!',
                  ),
                ]),
                const SizedBox(height: 16),

                // ─── SECTION 3: RULES OF THE GAME ───
                _buildSectionHeader(
                  title: '3. Rules of the Game',
                  icon: Icons.casino_rounded,
                ),
                const SizedBox(height: 8),
                _buildCard([
                  _buildBullet(
                    title: 'The Deal',
                    description:
                        'A standard 52-card deck is dealt evenly to all players at the start.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'First Turn',
                    description:
                        'The player with the Ace of Spades (♠A) starts the game by playing it to the table.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'Follow the Suit',
                    description:
                        'Turns move clockwise. You MUST play a card of the same suit that was led if you have one.',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'Next Round Lead',
                    description:
                        'The highest card of the led suit must start the next round (Ace is highest). Leading is risky—other players can punish you if they lack that suit!',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'The Thulla (Punishment Penalty)',
                    description:
                        'Don\'t have the led suit? You give a "Punishment" card from any other suit! Whoever played the highest card of the led suit must pick up ALL cards on the table plus the penalty card!',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'Endless Loop Rule (5 Fresh Cards)',
                    description:
                        'If the final two players get stuck in a loop unable to finish because they hold cards of different suits, 5 fresh cards are dealt to each player from the played deck to break the deadlock and keep the battle going!',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'How to Win',
                    description:
                        'Play smart and shed your cards. As soon as your hand is empty, you are safe and finish in top ranking!',
                  ),
                  const SizedBox(height: 10),
                  _buildBullet(
                    title: 'The Donkey ("Gadha")',
                    description:
                        'The last remaining player left holding cards loses the match and becomes the Donkey!',
                  ),
                ]),
                const SizedBox(height: 20),

                // Got it button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      AudioService().playTapSound();
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE3B13C),
                      foregroundColor: const Color(0xFF2C1A0E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Got It, Let\'s Play!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({required String title, required IconData icon}) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFF2D87B), size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFFF2D87B),
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F5B30).withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD3AC47).withOpacity(0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildBullet({required String title, required String description}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6, right: 8),
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: Color(0xFFF2D87B),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFFC2C8A4),
                fontSize: 13.5,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(
                    color: Color(0xFFF2D87B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
