import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/card_model.dart';
import '../models/online_room_model.dart';

/// Handles all Firebase Realtime Database and Auth operations for online rooms.
class RoomRepository {
  final FirebaseAuth? _injectedAuth;
  final FirebaseDatabase? _injectedDb;

  RoomRepository({FirebaseAuth? auth, FirebaseDatabase? db})
      : _injectedAuth = auth,
        _injectedDb = db;

  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;
  FirebaseDatabase get _db => _injectedDb ?? FirebaseDatabase.instance;

  // ─── Auth ──────────────────────────────────────────────────────────────────

  String? _persistentUid;

  Future<String> signInAnonymously() async {
    if (_persistentUid != null) return _persistentUid!;

    final prefs = await SharedPreferences.getInstance();
    String? storedId = prefs.getString('persistent_device_user_id');

    if (storedId == null || storedId.isEmpty) {
      storedId =
          'dev_user_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      await prefs.setString('persistent_device_user_id', storedId);
    }

    _persistentUid = storedId;

    // Optional Firebase auth sign-in if Firebase Auth is used elsewhere
    try {
      if (_auth.currentUser == null) {
        await _auth.signInAnonymously();
      }
    } catch (e) {
      debugPrint('CHECK_ACTIVE_ROOM_ERROR: $e');
    }

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
      'lastSeen': now,
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

    // Check room meta
    final metaSnap = await _db.ref('rooms/$roomId/meta').get();
    if (!metaSnap.exists) throw Exception('Room data missing.');
    final meta = metaSnap.value as Map<Object?, Object?>;
    final status = meta['status'] as String? ?? 'waiting';

    if (status == 'completed') {
      throw Exception('This game has already ended.');
    }
    if (status != 'waiting') {
      throw Exception('This game is already in progress. You cannot join.');
    }

    final playersSnap = await _db.ref('rooms/$roomId/players').get();
    final playersMap = playersSnap.exists
        ? playersSnap.value as Map<Object?, Object?>
        : <Object?, Object?>{};

    // Check if this device is already in the room (same persistent UID)
    if (playersMap.containsKey(uid)) {
      // Already in room — just mark online again
      final now = DateTime.now().millisecondsSinceEpoch;
      final playerRef = _db.ref('rooms/$roomId/players/$uid');
      await playerRef.update({'isOnline': true, 'joinedAt': now, 'lastSeen': now});
      await playerRef.onDisconnect().update({'isOnline': false});
      return OnlineRoomModel.fromJson(roomId, meta);
    }

    // New player — check capacity
    final maxPlayers = meta['maxPlayers'] as int? ?? 4;
    if (playersMap.length >= maxPlayers) {
      throw Exception('Room is full ($maxPlayers/$maxPlayers players).');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final playerRef = _db.ref('rooms/$roomId/players/$uid');
    await playerRef.set({
      'uid': uid,
      'name': playerName,
      'isOnline': true,
      'joinedAt': now,
      'lastSeen': now,
    });
    await playerRef.onDisconnect().update({'isOnline': false});

    return OnlineRoomModel.fromJson(roomId, meta);
  }

  // ─── Streams ───────────────────────────────────────────────────────────────

  Stream<List<OnlinePlayerModel>> playersStream(String roomId) {
    return _db.ref('rooms/$roomId/players').onValue.map((event) {
      if (!event.snapshot.exists) return [];
      final data = event.snapshot.value as Map<Object?, Object?>;
      return data.entries
          .map(
            (e) => OnlinePlayerModel.fromJson(
              e.key as String,
              e.value as Map<Object?, Object?>,
            ),
          )
          .toList()
        ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    });
  }

  Stream<String> roomStatusStream(String roomId) {
    return _db.ref('rooms/$roomId/meta/status').onValue.map((event) {
      return event.snapshot.value as String? ?? 'waiting';
    });
  }

  Stream<Map<Object?, Object?>?> roomMetaStream(String roomId) {
    return _db.ref('rooms/$roomId/meta').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return event.snapshot.value as Map<Object?, Object?>?;
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
      return list.whereType<Map<Object?, Object?>>().map((c) {
        final m = c.map((k, v) => MapEntry(k.toString(), v));
        return PlayingCard.fromJson(m);
      }).toList();
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
    List<String>? wonPlayerUids,
  }) async {
    final updates = <String, dynamic>{};
    updates['rooms/$roomId/gameState'] = gameState;
    for (final uid in handsPerPlayer.keys) {
      updates['rooms/$roomId/hands/$uid/cards'] = handsPerPlayer[uid];
    }
    if (wonPlayerUids != null) {
      for (final uid in wonPlayerUids) {
        updates['rooms/$roomId/players/$uid/hasWon'] = true;
        updates['rooms/$roomId/wonPlayerUids/$uid'] = true;
      }
    }
    await _db.ref().update(updates);
  }

  Future<void> markPlayerWon(String roomId, String uid) async {
    final updates = <String, dynamic>{
      'rooms/$roomId/players/$uid/hasWon': true,
      'rooms/$roomId/wonPlayerUids/$uid': true,
    };
    await _db.ref().update(updates);
  }

  Stream<Set<String>> wonPlayerUidsStream(String roomId) {
    return _db.ref('rooms/$roomId/wonPlayerUids').onValue.map((event) {
      if (!event.snapshot.exists || event.snapshot.value == null) return <String>{};
      final data = event.snapshot.value as Map<Object?, Object?>;
      return data.keys.map((k) => k.toString()).toSet();
    });
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

  Future<void> completeRoom(String roomId, {String? donkeyUid, String? donkeyName}) async {
    // Mark as completed and phase as gameOver so it stops appearing as active.
    final updates = <String, dynamic>{
      'rooms/$roomId/meta/status': 'completed',
      'rooms/$roomId/gameState/phase': 'gameOver',
    };
    if (donkeyUid != null) updates['rooms/$roomId/gameState/donkeyPlayerUid'] = donkeyUid;
    if (donkeyName != null) updates['rooms/$roomId/gameState/donkeyPlayerName'] = donkeyName;
    await _db.ref().update(updates);
  }

  // ─── Presence Management ─────────────────────────────────────────────────

  /// Mark a player as online again (used by reassertPresence on reconnect and restart logic).
  Future<void> rejoinRoom(String roomId, String uid, [String? name]) async {
    final playerRef = _db.ref('rooms/$roomId/players/$uid');
    final updates = <String, dynamic>{
      'isOnline': true,
      'uid': uid,
      'lastActive': ServerValue.timestamp,
    };
    if (name != null && name.isNotEmpty) {
      updates['name'] = name;
    }
    await playerRef.update(updates);
    await playerRef.onDisconnect().update({'isOnline': false});
  }

  Future<OnlineRoomModel?> getActiveRoom(String roomId) async {
    final snap = await _db.ref('rooms/$roomId/meta').get();
    if (!snap.exists) return null;
    final meta = snap.value as Map<Object?, Object?>;
    final status = meta['status'] as String? ?? '';
    if (status != 'in_progress' && status != 'waiting') return null;
    return OnlineRoomModel.fromJson(roomId, meta);
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
    return list.whereType<Map<Object?, Object?>>().map((c) {
      final m = c.map((k, v) => MapEntry(k.toString(), v));
      return PlayingCard.fromJson(m);
    }).toList();
  }

  Future<void> restartRoom(String roomId, [String? initiatorUid, String? initiatorName]) async {
    final updates = <String, dynamic>{};
    updates['rooms/$roomId/meta/status'] = 'waiting';
    updates['rooms/$roomId/gameState'] = null;
    updates['rooms/$roomId/pendingAction'] = null;
    updates['rooms/$roomId/disconnectData'] = null;
    updates['rooms/$roomId/wonPlayerUids'] = null;

    if (initiatorUid != null) {
      updates['rooms/$roomId/meta/hostId'] = initiatorUid;
      updates['rooms/$roomId/players/$initiatorUid/isOnline'] = true;
      updates['rooms/$roomId/players/$initiatorUid/uid'] = initiatorUid;
      if (initiatorName != null && initiatorName.isNotEmpty) {
        updates['rooms/$roomId/players/$initiatorUid/name'] = initiatorName;
      }
      updates['rooms/$roomId/players/$initiatorUid/lastActive'] = ServerValue.timestamp;

      final playersSnap = await _db.ref('rooms/$roomId/players').get();
      if (playersSnap.exists) {
        final pMap = playersSnap.value as Map<Object?, Object?>;
        for (final uid in pMap.keys) {
          final strUid = uid.toString();
          if (strUid != initiatorUid) {
            // Keep their name and existing info intact; only set isOnline: false until they hit Replay
            updates['rooms/$roomId/players/$strUid/isOnline'] = false;
          }
        }
      }
    }

    await _db.ref().update(updates);

    if (initiatorUid != null) {
      final playerRef = _db.ref('rooms/$roomId/players/$initiatorUid');
      await playerRef.onDisconnect().update({'isOnline': false});
    }
  }

  Future<void> deleteRoom(String roomId, String roomCode) async {
    await _db.ref('rooms/$roomId').remove();
    await _db.ref('roomCodes/$roomCode').remove();
  }

  Future<void> leaveRoom(String roomId, String uid) async {
    await removePlayer(roomId, uid);
  }

  Future<void> forfeitRoom(String roomId, String forfeitingUid, String forfeitingName) async {
    final updates = <String, dynamic>{
      'rooms/$roomId/meta/status': 'completed',
      'rooms/$roomId/players/$forfeitingUid/isOnline': false,
      'rooms/$roomId/players/$forfeitingUid/lastSeen': 0,
      'rooms/$roomId/gameState/phase': 'gameOver',
      'rooms/$roomId/gameState/donkeyPlayerUid': forfeitingUid,
      'rooms/$roomId/gameState/donkeyPlayerName': forfeitingName,
    };
    await _db.ref().update(updates);
  }

  Future<void> updatePlayerPresence(String roomId, String uid) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.ref('rooms/$roomId/players/$uid').update({
      'lastSeen': now,
      'isOnline': true,
    });
  }

  Future<Map<String, List<PlayingCard>>> getAllHands(String roomId) async {
    final snap = await _db.ref('rooms/$roomId/hands').get();
    if (!snap.exists || snap.value == null) return {};
    final data = snap.value as Map<Object?, Object?>;
    final result = <String, List<PlayingCard>>{};
    for (final entry in data.entries) {
      final uid = entry.key as String;
      final val = entry.value as Map<Object?, Object?>?;
      final cardsList = val?['cards'] as List<Object?>?;
      if (cardsList != null) {
        result[uid] = cardsList
            .whereType<Map<Object?, Object?>>()
            .map((c) {
              final m = c.map((k, v) => MapEntry(k.toString(), v));
              return PlayingCard.fromJson(m);
            })
            .toList();
      }
    }
    return result;
  }
}
