import 'package:flutter/material.dart';
import 'dart:math';
import '../../../widgets/card_widget.dart';

class DealingAnimationWidget extends StatefulWidget {
  final VoidCallback onComplete;

  const DealingAnimationWidget({super.key, required this.onComplete});

  @override
  State<DealingAnimationWidget> createState() => _DealingAnimationWidgetState();
}

class _DealingAnimationWidgetState extends State<DealingAnimationWidget> with TickerProviderStateMixin {
  late AnimationController _shuffleController;
  late AnimationController _dealController;
  
  bool _isShuffling = true;
  int _cardsDealt = 0;
  final int _totalCardsToDealVisual = 26; // Visual representation of dealing

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
    
    for (int i = 0; i < _totalCardsToDealVisual; i++) {
      if (!mounted) return;
      setState(() {
        _cardsDealt++;
      });
      await Future.delayed(const Duration(milliseconds: 80));
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
        alignment: Alignment.center,
        children: [
          // The main deck in the center
          if (_cardsDealt < _totalCardsToDealVisual)
            AnimatedBuilder(
              animation: _shuffleController,
              builder: (context, child) {
                return Stack(
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
            
            return TweenAnimationBuilder<double>(
              key: ValueKey('deal_$index'),
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value * endY),
                  child: Transform.scale(
                    scale: 1.2 - (value * 0.5), // Shrink as they fly away
                    child: Opacity(
                      opacity: 1.0 - (value * 0.5), // Fade slightly as they fly away
                      child: CardWidget(card: null, faceUp: false, scale: 1.2),
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
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            )
          else if (_cardsDealt < _totalCardsToDealVisual)
            const Positioned(
              bottom: -60,
              child: Text(
                "Dealing cards...",
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
