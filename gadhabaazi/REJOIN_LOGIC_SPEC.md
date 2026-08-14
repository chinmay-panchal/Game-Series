# Rejoin Logic Specification & Flow

This document details the exact requirements and lifecycle of the **30-Second Disconnect & Rejoin System** in GadhaBaazi.

---

## 1. Session Persistence (When entering a room)
Whenever a user creates, joins, or rejoins an online room, the following parameters are saved in `SharedPreferences`:
- `active_online_room_id`
- `active_online_room_code`
- `active_online_player_name`
- `active_online_player_uid`

---

## 2. Leaving / Exiting / Force-Killing the App
When a player leaves the `OnlineGameScreen` (via back button, home gesture, or app force-kill):
1. `SharedPreferences` retains the `active_online_room_id` session.
2. Firebase RTDB presence sets `isOnline: false` (either explicitly on back press or via `onDisconnect()` when killed).
3. The remaining active player's device or the back action writes `disconnectData` in Firebase RTDB:
   - `disconnectedUid`: player UID
   - `disconnectedName`: player Name
   - `disconnectedAt`: current timestamp
   - `expiresAt`: current timestamp + 30000ms (30 seconds countdown)

---

## 3. HomeScreen Rejoin Check (`_checkActiveOnlineRoom`)
On `HomeScreen` launch or resume:
1. Read `active_online_room_id`, `active_online_room_code`, `active_online_player_name` from `SharedPreferences`.
2. **If no saved room ID exists**: Do not show Rejoin button.
3. **If saved room ID exists**: Query Firebase RTDB `rooms/$roomId/meta`:
   - If room does NOT exist or `status` is `'completed'`: Clear `SharedPreferences` session. No Rejoin button.
   - If room `status` is `'in_progress'` or `'waiting'`:
     - Fetch `disconnectData` from Firebase `rooms/$roomId/disconnectData`.
     - If `disconnectData` exists:
       `secondsRemaining = ((expiresAt - now) / 1000).ceil()`
     - If `disconnectData` is null (e.g. app was just killed/reopened before node was updated):
       Default `secondsRemaining = 30`.
     - **If `secondsRemaining > 0`**:
       - Render **Rejoin Button** (`assets/images/rejoin_online_game.png`) replacing the Play Online button.
       - Render **Top-Right Yellow Timer Circle** displaying `secondsRemaining`.
       - Start 1-second interval ticker updating `secondsRemaining`.
     - **If `secondsRemaining <= 0`**:
       - Clear `SharedPreferences` session.
       - Hide Rejoin button.

---

## 4. Rejoining Game (`onTap` Rejoin Button)
1. Stop countdown ticker.
2. Clear `disconnectData` node in Firebase RTDB and set `isOnline: true`.
3. Dispatch `RejoinExistingRoom` event to `OnlineBloc`.
4. Navigate to `OnlineGameScreen(isRejoin: true)` which skips the dealing animation.

// adb -s <serial> tcpip 5555
// adb connect 172.20.10.3:5555