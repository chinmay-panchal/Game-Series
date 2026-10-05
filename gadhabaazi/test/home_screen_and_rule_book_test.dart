import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gadhabaazi/blocs/game/game_bloc.dart';
import 'package:gadhabaazi/blocs/online/online_bloc.dart';
import 'package:gadhabaazi/engine/game_engine.dart';
import 'package:gadhabaazi/services/room_repository.dart';
import 'package:gadhabaazi/screens/home/home_screen.dart';
import 'package:gadhabaazi/screens/splash/splash_screen.dart' hide ImageButton;
import 'package:gadhabaazi/screens/online/online_mode_screen.dart';
import 'package:gadhabaazi/screens/online/waiting_room_screen.dart';
import 'package:gadhabaazi/models/online_room_model.dart';
import 'package:gadhabaazi/blocs/online/online_state.dart';
import 'package:gadhabaazi/widgets/rule_book_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableHomeScreen() {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => GameBloc(engine: GameEngine())),
        BlocProvider(create: (_) => OnlineBloc(repository: RoomRepository())),
      ],
      child: const MaterialApp(
        home: HomeScreen(),
      ),
    );
  }

  group('HomeScreen Rule Book & Walkthrough Tests', () {
    testWidgets('First launch displays walkthrough overlay pointing to rule book', (tester) async {
      SharedPreferences.setMockInitialValues({'hasSeenWalkthrough': false});

      await tester.pumpWidget(buildTestableHomeScreen());
      await tester.pump(const Duration(milliseconds: 100));
      // Advance clock past the 600ms delayed walkthrough timer
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Rule book icon exists
      expect(find.byIcon(Icons.menu_book_rounded), findsWidgets);

      // Walkthrough text is displayed
      expect(find.text('Tap here anytime to see how to play'), findsOneWidget);

      // Dismiss walkthrough by tapping the close button
      final closeBtn = find.byIcon(Icons.close);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // Walkthrough is now gone
      expect(find.text('Tap here anytime to see how to play'), findsNothing);

      // Verify preference was stored
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hasSeenWalkthrough'), isTrue);
    });

    testWidgets('Second launch (hasSeenWalkthrough: true) does not show walkthrough', (tester) async {
      SharedPreferences.setMockInitialValues({'hasSeenWalkthrough': true});

      await tester.pumpWidget(buildTestableHomeScreen());
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      // Rule book icon still exists
      expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);

      // Walkthrough is NOT shown
      expect(find.text('Tap here anytime to see how to play'), findsNothing);
    });

    testWidgets('Tapping Rule Book icon opens RuleBookSheet with accurate rules', (tester) async {
      SharedPreferences.setMockInitialValues({'hasSeenWalkthrough': true});

      await tester.pumpWidget(buildTestableHomeScreen());
      await tester.pumpAndSettle();

      // Tap rule book icon
      await tester.tap(find.byIcon(Icons.menu_book_rounded));
      await tester.pumpAndSettle();

      // RuleBookSheet is visible
      expect(find.byType(RuleBookSheet), findsOneWidget);
      expect(find.text('How to Play GadhaBaazi'), findsOneWidget);
      expect(find.text('1. How to Start'), findsOneWidget);

      // Scroll down to view the rest of the rules
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(find.text('2. Online Rooms'), findsOneWidget);
      expect(find.text('3. Rules of the Game'), findsOneWidget);
      // Check rich text content for rules
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('2 up to 26 players'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains('Endless Loop Rule') &&
              widget.text.toPlainText().contains('5 fresh cards'),
        ),
        findsOneWidget,
      );

      // Tap Close button in header to dismiss
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // RuleBookSheet is closed
      expect(find.byType(RuleBookSheet), findsNothing);
    });
  });

  group('HomeScreen Button Tap Isolation Tests', () {
    testWidgets('Tapping Play Offline triggers Player Count dialog, not Online', (tester) async {
      SharedPreferences.setMockInitialValues({'hasSeenWalkthrough': true});

      await tester.pumpWidget(buildTestableHomeScreen());
      await tester.pumpAndSettle();

      final offlineFinder = find.byWidgetPredicate(
        (widget) => widget is ImageButton && widget.assetPath == 'assets/images/play_offline.png',
      );
      final onlineFinder = find.byWidgetPredicate(
        (widget) => widget is ImageButton && widget.assetPath == 'assets/images/play_online.png',
      );

      expect(offlineFinder, findsOneWidget);
      expect(onlineFinder, findsOneWidget);

      // Check vertical gap between the two buttons
      final onlineRect = tester.getRect(onlineFinder);
      final offlineRect = tester.getRect(offlineFinder);
      final gap = offlineRect.top - onlineRect.bottom;
      expect(gap, greaterThanOrEqualTo(16.0));

      // Tap Play Offline
      await tester.tap(offlineFinder);
      await tester.pumpAndSettle();

      // Player count dialog opened
      expect(find.text('How many players? 🃏'), findsOneWidget);
      expect(find.text('Start Game'), findsOneWidget);
    });
  });

  group('SplashScreen First Screen Tests', () {
    testWidgets('SplashScreen immediately displays Let\'s Play button without delay', (tester) async {
      SharedPreferences.setMockInitialValues({'hasSeenWalkthrough': true});

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => GameBloc(engine: GameEngine())),
            BlocProvider(create: (_) => OnlineBloc(repository: RoomRepository())),
          ],
          child: const MaterialApp(
            home: SplashScreen(),
          ),
        ),
      );

      // On the very first pump (no timer/animation waiting needed), Let's Play button is present
      final letsPlayFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/images/lets_play.png',
      );
      expect(letsPlayFinder, findsOneWidget);

      // Tap Let's Play
      await tester.tap(letsPlayFinder);
      await tester.pumpAndSettle();

      // Should navigate to HomeScreen
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  });

  group('OnlineModeScreen & WaitingRoomScreen Tests', () {
    testWidgets('WaitingRoomScreen filters out offline players and shows Waiting for players when < 2 online', (tester) async {
      final room = OnlineRoomModel(
        roomId: 'test-room',
        roomCode: 'ABC123',
        hostId: 'host-1',
        status: 'waiting',
        maxPlayers: 4,
        createdAt: 1000,
      );
      final players = [
        OnlinePlayerModel(uid: 'host-1', name: 'Alice', isOnline: true, joinedAt: 1000),
        OnlinePlayerModel(uid: 'guest-2', name: 'Bob', isOnline: false, joinedAt: 1001),
      ];

      final fakeOnlineBloc = OnlineBloc(repository: RoomRepository());
      // Emit waiting state with an offline player
      fakeOnlineBloc.emit(OnlineWaiting(
        room: room,
        players: players,
        isHost: true,
      ));

      await tester.pumpWidget(
        BlocProvider<OnlineBloc>.value(
          value: fakeOnlineBloc,
          child: const MaterialApp(
            home: WaitingRoomScreen(),
          ),
        ),
      );
      await tester.pump();

      // Offline warning text should NOT be shown
      expect(find.text('A player is offline — waiting to reconnect'), findsNothing);

      // Offline player Bob should be filtered out, leaving 1 player (Alice)
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);

      // Start button should show 'Waiting for players...' and be disabled
      expect(find.text('Waiting for players...'), findsOneWidget);
      final buttonFinder = find.byType(ElevatedButton);
      expect(buttonFinder, findsOneWidget);
      final elevatedButton = tester.widget<ElevatedButton>(buttonFinder);
      expect(elevatedButton.onPressed, isNull);
    });

    testWidgets('WaitingRoomScreen enables Start Game when all 2+ players are online', (tester) async {
      final room = OnlineRoomModel(
        roomId: 'test-room',
        roomCode: 'ABC123',
        hostId: 'host-1',
        status: 'waiting',
        maxPlayers: 4,
        createdAt: 1000,
      );
      final players = [
        OnlinePlayerModel(uid: 'host-1', name: 'Alice', isOnline: true, joinedAt: 1000),
        OnlinePlayerModel(uid: 'guest-2', name: 'Bob', isOnline: true, joinedAt: 1001),
      ];

      final fakeOnlineBloc = OnlineBloc(repository: RoomRepository());
      fakeOnlineBloc.emit(OnlineWaiting(
        room: room,
        players: players,
        isHost: true,
      ));

      await tester.pumpWidget(
        BlocProvider<OnlineBloc>.value(
          value: fakeOnlineBloc,
          child: const MaterialApp(
            home: WaitingRoomScreen(),
          ),
        ),
      );
      await tester.pump();

      // No offline warning text
      expect(find.text('A player is offline — waiting to reconnect'), findsNothing);

      // Start button should show '▶  Start Game' and be enabled
      expect(find.text('▶  Start Game'), findsOneWidget);
      final buttonFinder = find.byType(ElevatedButton);
      final elevatedButton = tester.widget<ElevatedButton>(buttonFinder);
      expect(elevatedButton.onPressed, isNotNull);
    });

    testWidgets('WaitingRoomScreen hides Start Game button from non-host guest and displays waiting text', (tester) async {
      final room = OnlineRoomModel(
        roomId: 'test-room',
        roomCode: 'ABC123',
        hostId: 'host-1',
        status: 'waiting',
        maxPlayers: 4,
        createdAt: 1000,
      );
      final players = [
        OnlinePlayerModel(uid: 'host-1', name: 'Alice', isOnline: true, joinedAt: 1000),
        OnlinePlayerModel(uid: 'guest-2', name: 'Bob', isOnline: true, joinedAt: 1001),
      ];

      final fakeOnlineBloc = OnlineBloc(repository: RoomRepository());
      fakeOnlineBloc.emit(OnlineWaiting(
        room: room,
        players: players,
        isHost: false, // guest!
      ));

      await tester.pumpWidget(
        BlocProvider<OnlineBloc>.value(
          value: fakeOnlineBloc,
          child: const MaterialApp(
            home: WaitingRoomScreen(),
          ),
        ),
      );
      await tester.pump();

      // Start Game button should NOT exist for non-host
      expect(find.text('▶  Start Game'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);

      // Waiting text should be displayed
      expect(find.text('Waiting for the host to start the game…'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
    });

    testWidgets('OnlineModeScreen displays loading modal when state is OnlineLoading', (tester) async {
      final fakeOnlineBloc = OnlineBloc(repository: RoomRepository());
      fakeOnlineBloc.emit(const OnlineLoading('Creating room...'));

      await tester.pumpWidget(
        BlocProvider<OnlineBloc>.value(
          value: fakeOnlineBloc,
          child: const MaterialApp(
            home: OnlineModeScreen(),
          ),
        ),
      );
      await tester.pump();

      // Modal loader and message should be shown without underline
      final textFinder = find.text('Creating room...');
      expect(textFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.decoration, TextDecoration.none);
      expect(find.ancestor(of: textFinder, matching: find.byType(Material)), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}


