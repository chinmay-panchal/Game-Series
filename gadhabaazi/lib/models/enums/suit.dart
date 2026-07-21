enum Suit {
  spades,
  hearts,
  diamonds,
  clubs;

  String get symbol {
    switch (this) {
      case Suit.spades: return '♠';
      case Suit.hearts: return '♥';
      case Suit.diamonds: return '♦';
      case Suit.clubs: return '♣';
    }
  }

  bool get isRed => this == Suit.hearts || this == Suit.diamonds;
}
