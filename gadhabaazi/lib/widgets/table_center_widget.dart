import 'package:flutter/material.dart';
import '../models/round_model.dart';
import '../models/played_card.dart';
import 'card_widget.dart';
import 'dart:math';

class TableCenterWidget extends StatelessWidget {
  final RoundModel? currentRound;
  final PlayedCard? highestCard;

  const TableCenterWidget({
    super.key,
    required this.currentRound,
    this.highestCard,
  });

  @override
  Widget build(BuildContext context) {
    if (currentRound == null || currentRound!.playedCards.isEmpty) {
      return const Center(
        child: Text(
          "Table Empty",
          style: TextStyle(
            color: Colors.white24,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return SizedBox(
      width: 250,
      height: 250,
      child: Stack(
        alignment: Alignment.center,
        children: List.generate(currentRound!.playedCards.length, (index) {
          final pc = currentRound!.playedCards[index];
          final isHighest = pc == highestCard;
          
          // Random-ish rotation based on index so it looks scattered
          final random = Random(pc.playerId.hashCode ^ pc.card.hashCode);
          final angle = (random.nextDouble() * 0.5) - 0.25;

          return Positioned(
            child: Transform.rotate(
              angle: angle,
              child: CardWidget(
                card: pc.card,
                isSelected: isHighest,
                scale: 1.2,
              ),
            ),
          );
        }),
      ),
    );
  }
}
