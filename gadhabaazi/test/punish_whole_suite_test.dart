import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:gadhabaazi/models/card_model.dart';
import 'package:gadhabaazi/models/enums/suit.dart';
import 'package:gadhabaazi/models/enums/rank.dart';
import 'package:gadhabaazi/models/player_model.dart';
import 'package:gadhabaazi/models/round_model.dart';
import 'package:gadhabaazi/models/played_card.dart';
import 'package:gadhabaazi/engine/game_engine.dart';
import 'package:gadhabaazi/blocs/game/game_bloc.dart';
import 'package:gadhabaazi/blocs/game/game_state.dart';
import 'package:gadhabaazi/screens/game/widgets/game_table_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Punish Whole Suite UI Tests', () {
    testWidgets('Shows yellow Punish Whole Suite button when player has only one suit remaining', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p1 = Player(id: 'p1', name: 'Player 1', hand: [
        PlayingCard(suit: Suit.hearts, rank: Rank.five),
      ]);
      final p2Spades = [
        PlayingCard(suit: Suit.spades, rank: Rank.three),
        PlayingCard(suit: Suit.spades, rank: Rank.seven),
        PlayingCard(suit: Suit.spades, rank: Rank.king),
      ];
      final p2 = Player(id: 'p2', name: 'Player 2', hand: List.from(p2Spades));

      final round = RoundModel(
        roundNumber: 2,
        suit: Suit.hearts,
        leadPlayerId: 'p1',
        playedCards: [
          PlayedCard(playerId: 'p1', card: PlayingCard(suit: Suit.hearts, rank: Rank.ace)),
        ],
      );

      final state = GamePlayerTurn(
        activePlayer: p2,
        otherPlayers: [p1],
        currentRound: round,
        isFirstTurn: false,
        isHandRevealed: true,
        currentSuit: Suit.hearts,
        playerNames: {'p1': 'Player 1', 'p2': 'Player 2'},
        highestCard: round.playedCards.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => GameBloc(engine: GameEngine()),
            child: GameTableView(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Yellow Punish Whole Suite button must be visible
      expect(find.text('Punish Whole Suite (3 Cards)'), findsOneWidget);

      // Verify button has yellow color
      final buttonWidget = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Punish Whole Suite (3 Cards)'),
          matching: find.byType(ElevatedButton),
        ),
      );
      final bgColor = buttonWidget.style?.backgroundColor?.resolve({});
      expect(bgColor, equals(const Color(0xFFE3B13C)));
    });

    testWidgets('Does NOT show Punish Whole Suite button when player has multiple suits remaining (e.g. 1 spade, 2 diamonds)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p1 = Player(id: 'p1', name: 'Player 1', hand: [
        PlayingCard(suit: Suit.hearts, rank: Rank.five),
      ]);
      final p2MixedHand = [
        PlayingCard(suit: Suit.spades, rank: Rank.three),
        PlayingCard(suit: Suit.diamonds, rank: Rank.seven),
        PlayingCard(suit: Suit.diamonds, rank: Rank.king),
      ];
      final p2 = Player(id: 'p2', name: 'Player 2', hand: List.from(p2MixedHand));

      final round = RoundModel(
        roundNumber: 2,
        suit: Suit.hearts,
        leadPlayerId: 'p1',
        playedCards: [
          PlayedCard(playerId: 'p1', card: PlayingCard(suit: Suit.hearts, rank: Rank.ace)),
        ],
      );

      final state = GamePlayerTurn(
        activePlayer: p2,
        otherPlayers: [p1],
        currentRound: round,
        isFirstTurn: false,
        isHandRevealed: true,
        currentSuit: Suit.hearts,
        playerNames: {'p1': 'Player 1', 'p2': 'Player 2'},
        highestCard: round.playedCards.first,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider(
            create: (_) => GameBloc(engine: GameEngine()),
            child: GameTableView(state: state),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Yellow Punish Whole Suite button must NOT be visible
      expect(find.textContaining('Punish Whole Suite'), findsNothing);

      // Select a card (e.g. ♠3)
      await tester.tap(find.text('3').first);
      await tester.pumpAndSettle();

      // Still must NOT show Punish Whole Suite
      expect(find.textContaining('Punish Whole Suite'), findsNothing);

      // Only shows "Give Punishment Card"
      expect(find.text('Give Punishment Card'), findsOneWidget);
    });
  });
}
