import 'package:flutter/material.dart';
import '../models/enums/suit.dart';
import '../core/constants/app_colors.dart';

class SuitIndicatorWidget extends StatelessWidget {
  final Suit? suit;

  const SuitIndicatorWidget({super.key, this.suit});

  @override
  Widget build(BuildContext context) {
    if (suit == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.black.withAlpha(128),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.goldAccent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Current Suit: ',
            style: TextStyle(color: const Color(0xFFC2C8A4), fontSize: 16),
          ),
          Text(
            suit!.symbol,
            style: TextStyle(
              color: suit!.isRed ? AppColors.redCard : const Color(0xFFC2C8A4),
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
