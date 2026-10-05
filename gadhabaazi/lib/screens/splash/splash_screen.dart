import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/audio_service.dart';
import '../home/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/splash_background.png'), context);
    precacheImage(const AssetImage('assets/images/starting.png'), context);
    precacheImage(const AssetImage('assets/images/lets_play.png'), context);
    precacheImage(const AssetImage('assets/images/play_online.png'), context);
    precacheImage(const AssetImage('assets/images/play_offline.png'), context);
  }

  @override
  void initState() {
    super.initState();
    AudioService().playSplashBgm();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double maxLogoHeight = size.height * 0.35;
    final double maxLogoWidth = size.width * 0.75;
    final double logoSize = (maxLogoHeight < maxLogoWidth ? maxLogoHeight : maxLogoWidth).clamp(100.0, 240.0);

    final double maxBtnHeight = size.height * 0.28;
    final double maxBtnWidth = size.width * 0.70;
    final double btnSize = (maxBtnHeight < maxBtnWidth ? maxBtnHeight : maxBtnWidth).clamp(110.0, 240.0);

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/splash_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              // Smash Logo
              Image.asset(
                'assets/images/starting.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 20),
              // Hint text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  "hint: Play smart & Get rid of all your cards.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cinzel(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFF2D87B), // Soft gold/yellow hint
                    shadows: [
                      const Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(2, 2),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 1),
              // Image Button
              ImageButton(
                assetPath: 'assets/images/lets_play.png',
                height: btnSize,
                onTap: () {
                  Navigator.of(context).pushReplacement(
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          const HomeScreen(),
                      transitionsBuilder:
                          (context, animation, secondaryAnimation, child) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                    ),
                  );
                },
              ),
              const Spacer(flex: 1),
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
    final double buttonWidth = widget.width ?? widget.height;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) {
        setState(() => _isPressed = true);
        AudioService().playTapSound();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: SizedBox(
          width: buttonWidth,
          height: widget.height,
          child: Image.asset(
            widget.assetPath,
            width: buttonWidth,
            height: widget.height,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
