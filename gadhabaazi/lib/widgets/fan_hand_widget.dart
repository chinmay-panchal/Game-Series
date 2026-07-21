import 'package:flutter/material.dart';
import 'dart:math';
import '../models/card_model.dart';
import 'card_widget.dart';

class FanHandWidget extends StatelessWidget {
  final List<PlayingCard> cards;
  final PlayingCard? selectedCard;
  final Function(PlayingCard) onCardTap;
  final bool Function(PlayingCard) isCardEnabled;

  const FanHandWidget({
    super.key,
    required this.cards,
    this.selectedCard,
    required this.onCardTap,
    required this.isCardEnabled,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const SizedBox(height: 150);
    }

    return SizedBox(
      height: 150,
      width: double.infinity,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: List.generate(cards.length, (index) {
          final card = cards[index];
          
          // Calculate angle and offset for the fan effect
          final double totalAngle = pi / 3; // 60 degrees spread
          final double startAngle = -totalAngle / 2;
          final double angleStep = cards.length > 1 ? totalAngle / (cards.length - 1) : 0;
          final double angle = cards.length == 1 ? 0 : startAngle + (index * angleStep);

          // Calculate vertical offset to make it look like an arc
          final double arcHeight = 30.0;
          final double normalizedPos = cards.length > 1 ? (index / (cards.length - 1)) * 2 - 1 : 0;
          final double yOffset = arcHeight * (1 - (normalizedPos * normalizedPos));

          return AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: yOffset,
            child: Transform.rotate(
              angle: angle,
              alignment: Alignment.bottomCenter,
              child: CardWidget(
                card: card,
                isSelected: card == selectedCard,
                disabled: !isCardEnabled(card),
                onTap: () => onCardTap(card),
              ),
            ),
          );
        }),
      ),
    );
  }
}
