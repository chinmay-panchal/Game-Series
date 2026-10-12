import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gadhabaazi/blocs/online/online_bloc.dart';
import 'package:gadhabaazi/blocs/online/online_event.dart';
import 'package:gadhabaazi/blocs/online/online_state.dart';
import 'package:gadhabaazi/models/online_room_model.dart';
import 'package:gadhabaazi/models/card_model.dart';
import 'package:gadhabaazi/services/room_repository.dart';

class MockRoomRepository extends Fake implements RoomRepository {
  bool forfeitCalled = false;
  String? forfeitedUid;
  String? forfeitedName;

  bool leaveRoomCalled = false;
  String? leftUid;

  bool completeRoomCalled = false;
  bool claimHostCalled = false;

  final StreamController<List<OnlinePlayerModel>> _playersCtrl =
      StreamController<List<OnlinePlayerModel>>.broadcast();
  final StreamController<Map<Object?, Object?>?> _roomMetaCtrl =
      StreamController<Map<Object?, Object?>?>.broadcast();
  final StreamController<bool> _connectionCtrl =
      StreamController<bool>.broadcast();
  final StreamController<Map<Object?, Object?>?> _gameStateCtrl =
      StreamController<Map<Object?, Object?>?>.broadcast();
  final StreamController<Map<Object?, Object?>?> _pendingActionCtrl =
      StreamController<Map<Object?, Object?>?>.broadcast();
  final StreamController<List<PlayingCard>> _handCtrl =
      StreamController<List<PlayingCard>>.broadcast();

  @override
  Stream<List<OnlinePlayerModel>> playersStream(String roomId) =>
      _playersCtrl.stream;

  @override
  Stream<Map<Object?, Object?>?> roomMetaStream(String roomId) =>
      _roomMetaCtrl.stream;

  @override
  Stream<bool> get onConnectionChanged => _connectionCtrl.stream;

  @override
  Stream<Map<Object?, Object?>?> gameStateStream(String roomId) =>
      _gameStateCtrl.stream;

  @override
  Stream<Map<Object?, Object?>?> pendingActionStream(String roomId) =>
      _pendingActionCtrl.stream;

  @override
  Stream<List<PlayingCard>> myHandStream(String roomId, String uid) =>
      _handCtrl.stream;

  @override
  String? get currentUid => 'test-user-uid';

  @override
  Future<OnlineRoomModel> createRoom({
    required String hostName,
    required int maxPlayers,
  }) async {
    return const OnlineRoomModel(
      roomId: 'test-room-123',
      roomCode: '1234',
      hostId: 'test-user-uid',
      status: 'in_progress',
      maxPlayers: 4,
      createdAt: 1000,
    );
  }

  @override
  Future<void> updatePlayerPresence(String roomId, String uid) async {}

  @override
  Future<void> forfeitRoom(String roomId, String forfeitingUid, String forfeitingName) async {
    forfeitCalled = true;
    forfeitedUid = forfeitingUid;
    forfeitedName = forfeitingName;
  }

  @override
  Future<void> leaveRoom(String roomId, String uid) async {
    leaveRoomCalled = true;
    leftUid = uid;
  }

  @override
  Future<void> completeRoom(String roomId) async {
    completeRoomCalled = true;
  }

  @override
  Future<void> claimHost(String roomId, String newHostUid) async {
    claimHostCalled = true;
  }

  @override
  Future<Map<String, List<PlayingCard>>> getAllHands(String roomId) async => {};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (methodCall) async => 1,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (methodCall) async => 1,
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Online Win and Leave Rules Tests', () {
    test('isPlayerWon returns true when player UID is in finishedPlayerUids', () async {
      final mockRepo = MockRoomRepository();
      final bloc = OnlineBloc(repository: mockRepo);

      expect(bloc.isPlayerWon('u1'), isFalse);

      bloc.add(RemoteGameStateUpdated({
        'phase': 'playerTurn',
        'activePlayerIndex': 0,
        'playerOrder': ['u1', 'u2'],
        'finishedPlayerUids': ['u1'],
      }));
      await pumpEventQueue();

      expect(bloc.isPlayerWon('u1'), isTrue);
      expect(bloc.isPlayerWon('u2'), isFalse);

      await bloc.close();
    });

    test('When a player has already won, leaving the game does NOT make them donkey', () async {
      final mockRepo = MockRoomRepository();
      final bloc = OnlineBloc(repository: mockRepo);

      // Simulate guest in an active game where they have already finished all cards
      bloc.add(RemoteGameStateUpdated({
        'phase': 'playerTurn',
        'activePlayerIndex': 1,
        'playerOrder': ['u1', 'u2'],
        'finishedPlayerUids': ['u1'],
      }));
      await pumpEventQueue();

      // Trigger leave
      bloc.add(OnlineLeaveRoom());
      await pumpEventQueue();

      // forfeitRoom was NOT called because player already won!
      expect(mockRepo.forfeitCalled, isFalse);

      await bloc.close();
    });

    test('When an already-won player goes offline, other players do NOT forfeit', () async {
      final mockRepo = MockRoomRepository();
      final bloc = OnlineBloc(repository: mockRepo);

      // Set up game with 3 players
      final players = [
        const OnlinePlayerModel(uid: 'u1', name: 'WinnerAlice', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u2', name: 'PlayingBob', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u3', name: 'PlayingCharlie', isOnline: true, joinedAt: 0),
      ];

      bloc.add(PlayersUpdated(players));
      await pumpEventQueue();

      // WinnerAlice has already finished
      bloc.add(RemoteGameStateUpdated({
        'phase': 'playerTurn',
        'activePlayerIndex': 1,
        'playerOrder': ['u1', 'u2', 'u3'],
        'finishedPlayerUids': ['u1'],
      }));
      await pumpEventQueue();

      // Now WinnerAlice leaves (goes offline)
      final playersAfterAliceLeaves = [
        const OnlinePlayerModel(uid: 'u1', name: 'WinnerAlice', isOnline: false, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u2', name: 'PlayingBob', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u3', name: 'PlayingCharlie', isOnline: true, joinedAt: 0),
      ];

      bloc.add(PlayersUpdated(playersAfterAliceLeaves));
      await pumpEventQueue();

      // Game does NOT forfeit with WinnerAlice as donkey!
      expect(mockRepo.forfeitCalled, isFalse);

      await bloc.close();
    });

    test('When an UN-WON player goes offline during active game, they forfeit as donkey', () async {
      final mockRepo = MockRoomRepository();
      final bloc = OnlineBloc(repository: mockRepo);

      bloc.add(CreateRoom(hostName: 'WinnerAlice', maxPlayers: 4));
      await pumpEventQueue();

      // Set up game with 3 players
      final players = [
        const OnlinePlayerModel(uid: 'u1', name: 'WinnerAlice', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u2', name: 'LeaverBob', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u3', name: 'PlayingCharlie', isOnline: true, joinedAt: 0),
      ];

      bloc.add(PlayersUpdated(players));
      await pumpEventQueue();

      // WinnerAlice has won, Bob and Charlie still have cards
      bloc.add(RemoteGameStateUpdated({
        'phase': 'playerTurn',
        'activePlayerIndex': 1,
        'playerOrder': ['u1', 'u2', 'u3'],
        'finishedPlayerUids': ['u1'],
      }));
      await pumpEventQueue();

      // LeaverBob (who has NOT won) goes offline
      final playersAfterBobLeaves = [
        const OnlinePlayerModel(uid: 'u1', name: 'WinnerAlice', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u2', name: 'LeaverBob', isOnline: false, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u3', name: 'PlayingCharlie', isOnline: true, joinedAt: 0),
      ];

      bloc.add(PlayersUpdated(playersAfterBobLeaves));
      await pumpEventQueue();

      // LeaverBob forfeits and is made donkey!
      expect(mockRepo.forfeitCalled, isTrue);
      expect(mockRepo.forfeitedUid, equals('u2'));
      expect(mockRepo.forfeitedName, equals('LeaverBob'));

      await bloc.close();
    });

    test('When only 1 unfinished player remains after others finished, they become donkey', () async {
      final mockRepo = MockRoomRepository();
      final bloc = OnlineBloc(repository: mockRepo);

      bloc.add(CreateRoom(hostName: 'WinnerAlice', maxPlayers: 4));
      await pumpEventQueue();

      final players = [
        const OnlinePlayerModel(uid: 'u1', name: 'WinnerAlice', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u2', name: 'WinnerBob', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u3', name: 'LastCharlie', isOnline: true, joinedAt: 0),
      ];

      bloc.add(PlayersUpdated(players));
      await pumpEventQueue();

      // Alice and Bob already won!
      bloc.add(RemoteGameStateUpdated({
        'phase': 'playerTurn',
        'activePlayerIndex': 2,
        'playerOrder': ['u1', 'u2', 'u3'],
        'finishedPlayerUids': ['u1', 'u2'],
      }));
      await pumpEventQueue();

      // WinnerBob exits after winning
      final playersAfterBobLeaves = [
        const OnlinePlayerModel(uid: 'u1', name: 'WinnerAlice', isOnline: true, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u2', name: 'WinnerBob', isOnline: false, joinedAt: 0),
        const OnlinePlayerModel(uid: 'u3', name: 'LastCharlie', isOnline: true, joinedAt: 0),
      ];

      OnlineState? finalState;
      final sub = bloc.stream.listen((s) => finalState = s);

      bloc.add(PlayersUpdated(playersAfterBobLeaves));
      await pumpEventQueue();

      // Since only Charlie is left with cards, Charlie is the donkey
      expect(finalState, isA<OnlineGameFinished>());
      final finished = finalState as OnlineGameFinished;
      expect(finished.donkeyName, equals('LastCharlie'));
      expect(finished.finishingOrder, containsAllInOrder(['WinnerAlice', 'WinnerBob', 'LastCharlie']));

      await sub.cancel();
      await bloc.close();
    });
  });
}
