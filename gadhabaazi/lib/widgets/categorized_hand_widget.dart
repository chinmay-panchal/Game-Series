import 'package:flutter/material.dart';
import '../models/card_model.dart';
import '../models/enums/suit.dart';
import '../core/constants/app_colors.dart';
import 'card_widget.dart';

class CategorizedHandWidget extends StatefulWidget {
  final List<PlayingCard> cards;
  final PlayingCard? selectedCard;
  final Function(PlayingCard) onCardTap;
  final bool Function(PlayingCard) isCardEnabled;

  final Suit? currentSuit;

  const CategorizedHandWidget({
    super.key,
    required this.cards,
    this.selectedCard,
    required this.onCardTap,
    required this.isCardEnabled,
    this.currentSuit,
  });

  @override
  State<CategorizedHandWidget> createState() => _CategorizedHandWidgetState();
}

class _CategorizedHandWidgetState extends State<CategorizedHandWidget> {
  Suit? _selectedSuit;

  @override
  void initState() {
    super.initState();
    _autoSelectSuit();
  }

  @override
  void didUpdateWidget(CategorizedHandWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cards != oldWidget.cards || widget.currentSuit != oldWidget.currentSuit) {
      _autoSelectSuit();
    }
  }

  void _autoSelectSuit() {
    if (widget.cards.isEmpty) {
      _selectedSuit = null;
      return;
    }

    // Auto-select active round suit if user has matching cards
    if (widget.currentSuit != null && widget.cards.any((c) => c.suit == widget.currentSuit)) {
      setState(() {
        _selectedSuit = widget.currentSuit;
      });
      return;
    }

    // Keep selected suit if player still has cards of that suit
    if (_selectedSuit != null && widget.cards.any((c) => c.suit == _selectedSuit)) {
      return;
    }
    // Select first available suit
    setState(() {
      _selectedSuit = widget.cards.first.suit;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return const SizedBox(height: 200);
    }

    // Group cards by suit
    final Map<Suit, List<PlayingCard>> cardsBySuit = {};
    for (var suit in Suit.values) {
      cardsBySuit[suit] = [];
    }
    for (var card in widget.cards) {
      cardsBySuit[card.suit]!.add(card);
    }

    final filteredCards = cardsBySuit[_selectedSuit] ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Suit Tabs
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: Suit.values.map((suit) {
            final count = cardsBySuit[suit]!.length;
            final isSelected = _selectedSuit == suit;
            final isRed = suit.isRed;
            return GestureDetector(
              onTap: count > 0 ? () => setState(() => _selectedSuit = suit) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.goldAccent : AppColors.black.withAlpha(100),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      suit.symbol,
                      style: TextStyle(
                        fontSize: 20,
                        color: count == 0
                            ? AppColors.textSecondary.withAlpha(100)
                            : isSelected
                                ? AppColors.black
                                : (isRed ? AppColors.redCard : AppColors.white),
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        "$count",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? AppColors.black : AppColors.white,
                        ),
                      ),
                    ]
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        // Horizontal list of cards
        SizedBox(
          height: 160,
          child: filteredCards.isEmpty
              ? const Center(child: Text("No cards in this suit", style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredCards.length,
                  itemBuilder: (context, index) {
                    final card = filteredCards[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                        child: CardWidget(
                          card: card,
                          isSelected: widget.selectedCard == card,
                          disabled: !widget.isCardEnabled(card),
                          onTap: () => widget.onCardTap(card),
                          scale: 1.2,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
