import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_sizes.dart';

class CardWidget extends StatelessWidget {
  final PlayingCard? card;
  final bool faceUp;
  final VoidCallback? onTap;
  final bool isSelected;
  final double scale;
  final bool disabled;

  const CardWidget({
    super.key,
    required this.card,
    this.faceUp = true,
    this.onTap,
    this.isSelected = false,
    this.scale = 1.0,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final width = AppSizes.cardWidth * scale;
    final height = AppSizes.cardHeight * scale;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: width,
        height: height,
        transform: Matrix4.translationValues(0, isSelected ? -20 : 0, 0),
        decoration: BoxDecoration(
          color: faceUp ? Colors.white : AppColors.goldAccent,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(
            color: isSelected ? AppColors.goldAccent : const Color(0xFF1A2C1A),
            width: isSelected ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(77),
              blurRadius: isSelected ? 8 : 4,
              offset: Offset(0, isSelected ? 4 : 2),
            ),
          ],
        ),
        child: faceUp && card != null
            ? _buildCardFace()
            : _buildCardBack(),
      ),
    );
  }

  Widget _buildCardFace() {
    final textColor = card!.suit.isRed ? AppColors.redCard : AppColors.blackCard;

    return Stack(
      children: [
        // Top left
        Positioned(
          top: 4,
          left: 4,
          child: Column(
            children: [
              Text(
                card!.rank.label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                card!.suit.symbol,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        // Center
        Center(
          child: Text(
            card!.suit.symbol,
            style: TextStyle(
              color: textColor,
              fontSize: 32,
            ),
          ),
        ),
        // Bottom right (inverted)
        Positioned(
          bottom: 4,
          right: 4,
          child: Transform.rotate(
            angle: 3.14159,
            child: Column(
              children: [
                Text(
                  card!.rank.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  card!.suit.symbol,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (disabled)
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withAlpha(102),
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            ),
          ),
      ],
    );
  }

  Widget _buildCardBack() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.tableLightGreen,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: const Color(0xFF1A2C1A), width: 2),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/images/starting.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
