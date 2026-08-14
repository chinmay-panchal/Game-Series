import 'package:flutter/material.dart';
import '../models/round_model.dart';
import '../models/played_card.dart';
import 'card_widget.dart';
import 'dart:math';

class TableCenterWidget extends StatefulWidget {
  final RoundModel? currentRound;
  final PlayedCard? highestCard;
  final Map<String, String>? playerNames;

  const TableCenterWidget({
    super.key,
    required this.currentRound,
    this.highestCard,
    this.playerNames,
  });

  @override
  State<TableCenterWidget> createState() => _TableCenterWidgetState();
}

class _TableCenterWidgetState extends State<TableCenterWidget> {
  bool _isHoveredOrTapped = false;

  @override
  Widget build(BuildContext context) {
    if (widget.currentRound == null || widget.currentRound!.playedCards.isEmpty) {
      return const SizedBox.shrink();
    }

    final playedCards = widget.currentRound!.playedCards;
    final total = playedCards.length;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHoveredOrTapped = true),
      onExit: (_) => setState(() => _isHoveredOrTapped = false),
      child: GestureDetector(
        onTap: () => setState(() => _isHoveredOrTapped = !_isHoveredOrTapped),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isHoveredOrTapped ? max(300.0, total * 75.0) : 250,
          height: 250,
          alignment: Alignment.center,
          child: Stack(
            alignment: Alignment.center,
            children: List.generate(total, (index) {
              final pc = playedCards[index];
              final isHighest = pc == widget.highestCard;
              final displayName = widget.playerNames?[pc.playerId] ?? pc.playerId;

              final random = Random(pc.playerId.hashCode ^ pc.card.hashCode);
              final angle = _isHoveredOrTapped ? 0.0 : ((random.nextDouble() * 0.5) - 0.25);

              // Calculate horizontal fan offset when hovered/tapped
              final double offsetX = _isHoveredOrTapped
                  ? ((index - (total - 1) / 2) * 70.0)
                  : 0.0;

              return AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                left: _isHoveredOrTapped ? null : 0,
                right: _isHoveredOrTapped ? null : 0,
                child: Transform.translate(
                  offset: Offset(offsetX, 0),
                  child: Transform.rotate(
                    angle: angle,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CardWidget(
                          card: pc.card,
                          isSelected: isHighest,
                          scale: 1.1,
                        ),
                        if (_isHoveredOrTapped) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                color: const Color(0xFFC2C8A4),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
