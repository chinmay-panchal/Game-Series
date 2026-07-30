import 'dart:math';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card_model.dart';
import '../models/online_room_model.dart';

/// Handles all Firebase Realtime Database and Auth operations for online rooms.
class RoomRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _db = FirebaseDatabase.instance;

  // ─── Auth ──────────────────────────────────────────────────────────────────

  String? _persistentUid;

  Future<String> signInAnonymously() async {
    if (_persistentUid != null) return _persistentUid!;

    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('persistent_device_user_id');

    if (storedId == null || storedId.isEmpty) {
      storedId = 'dev_user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await prefs.setString('persistent_device_user_id', storedId);
    }

    _persistentUid = storedId;

    // Optional Firebase auth sign-in if Firebase Auth is used elsewhere
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
    } catch (_) {}

    return storedId;
  }

  String? get currentUid => _persistentUid ?? _auth.currentUser?.uid;

  // ─── Room Codes ────────────────────────────────────────────────────────────

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // No ambiguous chars
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ─── Create Room ───────────────────────────────────────────────────────────

  Future<OnlineRoomModel> createRoom({
    required String hostName,
    required int maxPlayers,
  }) async {
    final uid = await signInAnonymously();
    final roomCode = _generateRoomCode();
    final roomRef = _db.ref('rooms').push();
    final roomId = roomRef.key!;
    final now = DateTime.now().millisecondsSinceEpoch;

    final room = OnlineRoomModel(
      roomId: roomId,
      roomCode: roomCode,
      hostId: uid,
      status: 'waiting',
      maxPlayers: maxPlayers,
      createdAt: now,
    );

    // Write room meta
    await roomRef.child('meta').set(room.toJson());

    // Write this player (host) as the first player
    await roomRef.child('players/$uid').set({
      'uid': uid,
      'name': hostName,
      'isOnline': true,
      'joinedAt': now,
    });

    // Register room code lookup
    await _db.ref('roomCodes/$roomCode').set(roomId);

    // Set onDisconnect: mark host as offline (triggers host migration on client side)
    final playerRef = roomRef.child('players/$uid');
    await playerRef.onDisconnect().update({'isOnline': false});

    return room;
  }

  // ─── Join Room ─────────────────────────────────────────────────────────────

  Future<OnlineRoomModel> joinRoom({
    required String roomCode,
    required String playerName,
  }) async {
    final uid = await signInAnonymously();
    final upperCode = roomCode.toUpperCase().trim();

    // Lookup roomId by code
    final codeSnap = await _db.ref('roomCodes/$upperCode').get();
    if (!codeSnap.exists) {
      throw Exception('Room not found. Check the code and try again.');
    }
    final roomId = codeSnap.value as String;

    // Check room status
    final metaSnap = await _db.ref('rooms/$roomId/meta').get();
    if (!metaSnap.exists) throw Exception('Room data missing.');
    final meta = metaSnap.value as Map<Object?, Object?>;
    final status = meta['status'] as String? ?? 'waiting';
    if (status != 'waiting') {
      throw Exception('This game has already started. You cannot join now.');
    }

    // Check if room is full
    final playersSnap = await _db.ref('rooms/$roomId/players').get();
    final currentCount = playersSnap.exists
        ? (playersSnap.value as Map<Object?, Object?>).length
        : 0;
    final maxPlayers = meta['maxPlayers'] as int? ?? 4;
    if (currentCount >= maxPlayers) {
      throw Exception('Room is full ($maxPlayers/$maxPlayers players).');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final playerRef = _db.ref('rooms/$roomId/players/$uid');
    await playerRef.set({
      'uid': uid,
      'name': playerName,
      'isOnline': true,
      'joinedAt': now,
    });

    // Set onDisconnect
    await playerRef.onDisconnect().update({'isOnline': false});

    return OnlineRoomModel.fromJson(roomId, meta);
  }

  // ─── Streams ───────────────────────────────────────────────────────────────

  Stream<List<OnlinePlayerModel>> playersStream(String roomId) {
    return _db.ref('rooms/$roomId/players').onValue.map((event) {
      if (!event.snapshot.exists) return [];
      final data = event.snapshot.value as Map<Object?, Object?>;
      return data.entries
          .map((e) => OnlinePlayerModel.fromJson(
              e.key as String, e.value as Map<Object?, Object?>))
          .toList()
        ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    });
  }

  Stream<String> roomStatusStream(String roomId) {
    return _db.ref('rooms/$roomId/meta/status').onValue.map((event) {
      return event.snapshot.value as String? ?? 'waiting';
    });
  }

  Stream<Map<Object?, Object?>?> gameStateStream(String roomId) {
    return _db.ref('rooms/$roomId/gameState').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return event.snapshot.value as Map<Object?, Object?>?;
    });
  }

  Stream<Map<Object?, Object?>?> pendingActionStream(String roomId) {
    return _db.ref('rooms/$roomId/pendingAction').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return event.snapshot.value as Map<Object?, Object?>?;
    });
  }

  Stream<List<PlayingCard>> myHandStream(String roomId, String uid) {
    return _db.ref('rooms/$roomId/hands/$uid/cards').onValue.map((event) {
      if (!event.snapshot.exists) return [];
      final list = event.snapshot.value as List<Object?>;
      return list
          .whereType<Map<Object?, Object?>>()
          .map((c) {
            final m = c.map((k, v) => MapEntry(k.toString(), v));
            return PlayingCard.fromJson(m);
          })
          .toList();
    });
  }

  // ─── Game Start (Host only) ────────────────────────────────────────────────

  Future<void> startGame({
    required String roomId,
    required Map<String, dynamic> gameState,
    required Map<String, List<Map<String, dynamic>>> handsPerPlayer,
  }) async {
    final updates = <String, dynamic>{};
    updates['rooms/$roomId/meta/status'] = 'in_progress';
    updates['rooms/$roomId/gameState'] = gameState;
    for (final uid in handsPerPlayer.keys) {
      updates['rooms/$roomId/hands/$uid/cards'] = handsPerPlayer[uid];
    }
    await _db.ref().update(updates);
  }

  // ─── Write game state (Host only, after each move) ──────────────────────────

  Future<void> writeGameState({
    required String roomId,
    required Map<String, dynamic> gameState,
    required Map<String, List<Map<String, dynamic>>> handsPerPlayer,
  }) async {
    final updates = <String, dynamic>{};
    updates['rooms/$roomId/gameState'] = gameState;
    for (final uid in handsPerPlayer.keys) {
      updates['rooms/$roomId/hands/$uid/cards'] = handsPerPlayer[uid];
    }
    await _db.ref().update(updates);
  }

  // ─── Submit Move (Guest only) ──────────────────────────────────────────────

  Future<void> submitPendingAction({
    required String roomId,
    required String playerId,
    required String type, // 'playCard' | 'givePunishment'
    required String cardSuit,
    required String cardRank,
  }) async {
    await _db.ref('rooms/$roomId/pendingAction').set({
      'playerId': playerId,
      'type': type,
      'cardSuit': cardSuit,
      'cardRank': cardRank,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> clearPendingAction(String roomId) async {
    await _db.ref('rooms/$roomId/pendingAction').remove();
  }

  // ─── Host Migration ────────────────────────────────────────────────────────

  Future<void> claimHost(String roomId, String newHostUid) async {
    await _db.ref('rooms/$roomId/meta/hostId').set(newHostUid);
  }

  // ─── Remove disconnected player (Host only) ───────────────────────────────

  Future<void> removePlayer(String roomId, String uid) async {
    await _db.ref('rooms/$roomId/players/$uid').remove();
    await _db.ref('rooms/$roomId/hands/$uid').remove();
  }

  // ─── Complete game ─────────────────────────────────────────────────────────

  Future<void> completeRoom(String roomId) async {
    // Just mark as completed so it stops appearing as active.
    // We do NOT delete it here, otherwise guests won't receive the gameOver state.
    await _db.ref('rooms/$roomId/meta/status').set('completed');
  }

  // ─── Disconnect & Rejoin Management ─────────────────────────────────────

  Stream<Map<Object?, Object?>?> disconnectDataStream(String roomId) {
    return _db.ref('rooms/$roomId/disconnectData').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return event.snapshot.value as Map<Object?, Object?>?;
    });
  }

  Future<void> setDisconnectTimer(String roomId, String uid, String name) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + 30000; // 30 seconds timer
    await _db.ref('rooms/$roomId/disconnectData').set({
      'disconnectedUid': uid,
      'disconnectedName': name,
      'disconnectedAt': now,
      'expiresAt': expiresAt,
    });
  }

  Future<void> clearDisconnectData(String roomId) async {
    await _db.ref('rooms/$roomId/disconnectData').remove();
  }

  Future<OnlineRoomModel?> getActiveRoom(String roomId) async {
    final snap = await _db.ref('rooms/$roomId/meta').get();
    if (!snap.exists) return null;
    final meta = snap.value as Map<Object?, Object?>;
    final status = meta['status'] as String? ?? '';
    if (status != 'in_progress' && status != 'waiting') return null;
    return OnlineRoomModel.fromJson(roomId, meta);
  }

  Future<Map<Object?, Object?>?> getDisconnectData(String roomId) async {
    final snap = await _db.ref('rooms/$roomId/disconnectData').get();
    if (!snap.exists) return null;
    return snap.value as Map<Object?, Object?>;
  }

  Future<void> rejoinRoom(String roomId, String uid) async {
    await _db.ref('rooms/$roomId/players/$uid/isOnline').set(true);
    await clearDisconnectData(roomId);
    final playerRef = _db.ref('rooms/$roomId/players/$uid');
    await playerRef.onDisconnect().update({'isOnline': false});
  }

  // ─── Connection Monitoring ───────────────────────────────────────────────

  Stream<bool> get onConnectionChanged {
    return _db.ref('.info/connected').onValue.map((event) {
      return (event.snapshot.value as bool?) ?? true;
    });
  }

  Future<bool> isPlayerInRoom(String roomId, String uid) async {
    final snap = await _db.ref('rooms/$roomId/players/$uid').get();
    return snap.exists;
  }

  Future<Map<Object?, Object?>?> getGameState(String roomId) async {
    final snap = await _db.ref('rooms/$roomId/gameState').get();
    if (!snap.exists) return null;
    return snap.value as Map<Object?, Object?>?;
  }

  Future<List<PlayingCard>> getMyHand(String roomId, String uid) async {
    final snap = await _db.ref('rooms/$roomId/hands/$uid/cards').get();
    if (!snap.exists) return [];
    final list = snap.value as List<Object?>;
    return list
        .whereType<Map<Object?, Object?>>()
        .map((c) {
          final m = c.map((k, v) => MapEntry(k.toString(), v));
          return PlayingCard.fromJson(m);
        })
        .toList();
  }

  Future<void> restartRoom(String roomId) async {
    final updates = <String, dynamic>{};
    updates['rooms/$roomId/meta/status'] = 'waiting';
    updates['rooms/$roomId/gameState'] = null;
    updates['rooms/$roomId/pendingAction'] = null;
    updates['rooms/$roomId/disconnectData'] = null;
    await _db.ref().update(updates);
  }

  Future<void> deleteRoom(String roomId, String roomCode) async {
    await _db.ref('rooms/$roomId').remove();
    await _db.ref('roomCodes/$roomCode').remove();
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await _db.ref('rooms/$roomId/players/$uid/isOnline').set(false);
  }
}
