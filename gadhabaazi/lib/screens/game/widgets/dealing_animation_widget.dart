import 'package:flutter/material.dart';
import 'dart:math';
import '../../../widgets/card_widget.dart';
import '../../../services/audio_service.dart';

class DealingAnimationWidget extends StatefulWidget {
  final VoidCallback onComplete;
  final int totalCardsToDealVisual;

  const DealingAnimationWidget({
    super.key,
    required this.onComplete,
    this.totalCardsToDealVisual = 24,
  });

  @override
  State<DealingAnimationWidget> createState() => _DealingAnimationWidgetState();
}

class _DealingAnimationWidgetState extends State<DealingAnimationWidget> with TickerProviderStateMixin {
  late AnimationController _shuffleController;
  late AnimationController _dealController;
  
  bool _isShuffling = true;
  int _cardsDealt = 0;

  @override
  void initState() {
    super.initState();
    
    _shuffleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _dealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    // 1. Shuffle for a bit
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    
    setState(() {
      _isShuffling = false;
    });
    _shuffleController.stop();

    // 2. Deal cards one by one rapidly
    _dealController.forward();
    
    for (int i = 0; i < widget.totalCardsToDealVisual; i++) {
      if (!mounted) return;
      setState(() {
        _cardsDealt++;
      });
      if (i % 3 == 0) {
        AudioService().playTapSound();
      }
      await Future.delayed(const Duration(milliseconds: 60)); // smooth individual card out
    }

    // 3. Complete
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      widget.onComplete();
    }
  }

  @override
  void dispose() {
    _shuffleController.dispose();
    _dealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // The main deck in the center
          if (_cardsDealt < widget.totalCardsToDealVisual)
            AnimatedBuilder(
              animation: _shuffleController,
              builder: (context, child) {
                return Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: List.generate(5, (index) {
                    double offset = _isShuffling 
                        ? sin(_shuffleController.value * pi + index) * 15
                        : 0;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: CardWidget(card: null, faceUp: false, scale: 1.2),
                    );
                  }),
                );
              },
            ),

          // Cards flying out
          ...List.generate(_cardsDealt, (index) {
            bool toPlayer1 = index % 2 == 0;
            // Target position: Player 1 is bottom, Player 2 is top
            double endY = toPlayer1 ? MediaQuery.of(context).size.height / 2 : -MediaQuery.of(context).size.height / 2;
            // Add a slight horizontal offset to fan them out like a real hand
            double endX = (index % 4 - 1.5) * 30.0;
            
            return TweenAnimationBuilder<double>(
              key: ValueKey('deal_$index'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutQuint,
              builder: (context, value, child) {
                // Add a dynamic spin (2 full rotations)
                double spin = value * pi * 4 * (toPlayer1 ? 1 : -1);
                
                return Transform.translate(
                  offset: Offset(value * endX, value * endY),
                  child: Transform.rotate(
                    angle: spin,
                    child: Transform.scale(
                      scale: 1.2 - (value * 0.4), // Shrink slightly
                      child: Opacity(
                        opacity: 1.0 - (value * 0.3), // Keep more visible
                        child: CardWidget(card: null, faceUp: false, scale: 1.2),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
          
          if (_isShuffling)
            const Positioned(
              bottom: -60,
              child: Text(
                "Shuffling...",
                style: TextStyle(color: const Color(0xFFC2C8A4), fontSize: 20, fontWeight: FontWeight.bold),
              ),
            )
          else if (_cardsDealt < widget.totalCardsToDealVisual)
            const Positioned(
              bottom: -60,
              child: Text(
                "Dealing cards...",
                style: TextStyle(color: const Color(0xFFC2C8A4), fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
