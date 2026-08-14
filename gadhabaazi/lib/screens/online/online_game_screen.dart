import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/online/online_bloc.dart';
import '../../models/card_model.dart';
import '../../blocs/online/online_event.dart';
import '../../blocs/online/online_state.dart';
import '../../core/constants/app_colors.dart';

import '../../widgets/animated_background.dart';
import '../../widgets/premium_toast.dart';
import '../result/game_result_screen.dart';
import '../../widgets/suit_indicator_widget.dart';
import '../../widgets/categorized_hand_widget.dart';
import '../../widgets/table_center_widget.dart';
import '../../engine/history/move_history.dart';
import '../game/widgets/dealing_animation_widget.dart';
import '../../services/audio_service.dart';
import '../home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The main online game screen. Works for both host and guest.
class OnlineGameScreen extends StatefulWidget {
  final bool isRejoin;
  const OnlineGameScreen({super.key, this.isRejoin = false});

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen> {
  PlayingCard? _selectedCard;
  String? _lastActivePlayer;
  int _hostDisconnectSeconds = 0;
  Timer? _hostDisconnectTimer;
  Timer? _roundCompleteTimer;
  bool _autoRedistributeDispatched = false;
  bool _isDealing = true;

  @override
  void initState() {
    super.initState();
    // Skip dealing animation on rejoin or if game already in progress
    if (widget.isRejoin) {
      _isDealing = false;
      return;
    }
    final bloc = context.read<OnlineBloc>();
    final state = bloc.state;
    bool alreadyInProgress = false;
    if (state is OnlinePlayerTurn) {
      final playedCount = state.currentRound?.playedCards.length ?? 0;
      final roundNum = state.currentRound?.roundNumber ?? 1;
      if (roundNum > 1 || playedCount > 0) alreadyInProgress = true;
    } else if (state is OnlineWaitingForTurn) {
      final playedCount = state.currentRound?.playedCards.length ?? 0;
      final roundNum = state.currentRound?.roundNumber ?? 1;
      if (roundNum > 1 || playedCount > 0) alreadyInProgress = true;
    }
    if (alreadyInProgress) _isDealing = false;
  }

  @override
  void dispose() {
    _hostDisconnectTimer?.cancel();
    _roundCompleteTimer?.cancel();
    super.dispose();
  }

  void _startHostDisconnectCountdown(int seconds) {
    _hostDisconnectTimer?.cancel();
    setState(() => _hostDisconnectSeconds = seconds);
    _hostDisconnectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_hostDisconnectSeconds <= 1) {
        timer.cancel();
        setState(() => _hostDisconnectSeconds = 0);
      } else {
        setState(() => _hostDisconnectSeconds--);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnlineBloc, OnlineState>(
      listenWhen: (prev, curr) {
        if (curr is OnlineRedistributingCards) return true;
        if (curr is OnlineError) return true;
        if (curr is OnlineRoundCompleted) return true;
        if (curr is OnlineGameFinished) return true;
        if (curr is OnlinePlayerTurn) {
          // Always fire when unendingLoopDetected becomes true so we can auto-redistribute
          if (curr.unendingLoopDetected) return true;
          return _lastActivePlayer != curr.activePlayerName;
        }
        if (curr is OnlineWaitingForTurn) {
          return _lastActivePlayer != curr.activePlayerName;
        }
        return false;
      },
      listener: (context, state) {
        if (state is OnlineRedistributingCards) {
          setState(() => _isDealing = true);
          PremiumToast.show(
            context,
            '${state.disconnectedPlayerName} left! Redistributing their cards...',
            isError: true,
            duration: const Duration(seconds: 4),
          );
        } else if (state is OnlineError) {
          PremiumToast.show(context, state.message, isError: true);
        } else if (state is OnlineRoundCompleted) {
          // ── Auto-advance to next round after a brief pause ──
          _roundCompleteTimer?.cancel();
          if (state.isHost) {
            _roundCompleteTimer = Timer(const Duration(seconds: 2), () {
              if (mounted) {
                context.read<OnlineBloc>().add(OnlineStartNextRound());
              }
            });
          }

          // ── Punishment toast ──
          final myUid = context.read<OnlineBloc>().myUid;
          if (state.punishmentCard != null &&
              state.punishmentReceiverUid != null) {
            final punisherEngineId = state.completedRound.winnerId;
            final punisherName = punisherEngineId != null
                ? state.playerNames[punisherEngineId] ?? 'Someone'
                : 'Someone';

            if (myUid == state.punishmentReceiverUid) {
              final card = state.punishmentCard!;
              PremiumToast.show(
                context,
                '🎴 $punisherName punished you with ${card.rank.label}${card.suit.symbol}!',
                isError: true,
                duration: const Duration(seconds: 5),
              );
            } else {
              PremiumToast.show(
                context,
                '🎴 $punisherName punished ${state.punishmentReceiverName}!',
                isError: true,
                duration: const Duration(seconds: 4),
              );
            }
          }
        } else if (state is OnlinePlayerTurn) {
          // ── Auto-redistribute when loop detected (host only) ──
          if (state.unendingLoopDetected &&
              state.isHost &&
              !_autoRedistributeDispatched) {
            _autoRedistributeDispatched = true;
            context.read<OnlineBloc>().add(OnlineDistributeNewCards());
            PremiumToast.show(
              context,
              '🂯 Too few cards in play — redistributing cards to both players!',
              duration: const Duration(seconds: 4),
            );
            return;
          }

          // Reset flag once loop is resolved
          if (!state.unendingLoopDetected) {
            _autoRedistributeDispatched = false;
          }

          // ── Disconnect countdown ──
          final allPlayers = state.allPlayers;
          final offlineHost = allPlayers.firstWhere(
            (p) => !p.isOnline,
            orElse: () => allPlayers.first,
          );
          if (!offlineHost.isOnline && _hostDisconnectSeconds == 0) {
            _startHostDisconnectCountdown(30);
          } else if (allPlayers.every((p) => p.isOnline) &&
              _hostDisconnectSeconds > 0) {
            _hostDisconnectTimer?.cancel();
            setState(() => _hostDisconnectSeconds = 0);
          }
          _lastActivePlayer = state.activePlayerName;
          if (_lastActivePlayer != null) {
            PremiumToast.show(context, "${state.activePlayerName}'s Turn");
          }
          if (_selectedCard != null) setState(() => _selectedCard = null);
        } else if (state is OnlineWaitingForTurn) {
          _lastActivePlayer = state.activePlayerName;
          PremiumToast.show(context, "${state.activePlayerName}'s Turn");
          if (_selectedCard != null) setState(() => _selectedCard = null);
        } else if (state is OnlineGameFinished) {
          _roundCompleteTimer?.cancel();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => GameResultScreen(
                donkeyName: state.donkeyName,
                finishingOrder: state.finishingOrder,
                history: const MoveHistory(),
                isOnlineRoom: true,
              ),
            ),
          );
        }
      },
      builder: (context, state) {
        return WillPopScope(
          onWillPop: () async {
            AudioService().playTapSound();
            print('RJDBG WILLPOP: onWillPop triggered');
            final bloc = context.read<OnlineBloc>();
            final roomId = bloc.currentRoomId;
            final uid = bloc.myUid;
            final name = bloc.myName ?? 'Player';
            final roomCode = bloc.currentRoomCode;
            print(
              'RJDBG WILLPOP: bloc.currentRoomId=$roomId bloc.myUid=$uid bloc.myName=$name bloc.currentRoomCode=$roomCode',
            );

            try {
              if (roomId != null && uid != null) {
                final repo = bloc.repository;
                await repo.leaveRoom(roomId, uid);
                await repo.setDisconnectTimer(roomId, uid, name);
                print(
                  'RJDBG WILLPOP: leaveRoom + setDisconnectTimer called for roomId=$roomId',
                );

                final disconnectData = await repo.getDisconnectData(roomId);
                final expiresAt = disconnectData != null
                    ? (disconnectData['expiresAt'] as int? ?? 0)
                    : (DateTime.now().millisecondsSinceEpoch + 30000);

                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('active_online_room_id', roomId);
                if (roomCode != null)
                  await prefs.setString('active_online_room_code', roomCode);
                await prefs.setString('active_online_player_name', name);
                await prefs.setString('active_online_player_uid', uid);
                await prefs.setInt('active_online_expires_at', expiresAt);
                print(
                  'RJDBG WILLPOP: prefs re-saved, roomId=$roomId expiresAt=$expiresAt',
                );

                final verify = prefs.getString('active_online_room_id');
                print('RJDBG WILLPOP VERIFY: read-back roomId=$verify');
              } else {
                print(
                  'RJDBG WILLPOP: SKIPPED save — roomId or uid was null from bloc',
                );
              }
            } catch (e, st) {
              print('RJDBG WILLPOP ERROR: $e');
              print('RJDBG WILLPOP STACK: $st');
            }

            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
              );
            }
            return false;
          },
          child: Scaffold(
            body: Stack(
              children: [
                const AnimatedBackground(child: SizedBox.expand()),
                SafeArea(
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        _buildHeader(context, state),
                        const Spacer(),
                        Builder(
                          builder: (ctx) {
                            // Only skip dealing animation when rejoining an in-progress game
                            if (_isDealing && widget.isRejoin) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted && _isDealing) {
                                  setState(() => _isDealing = false);
                                }
                              });
                            }
                            return _isDealing
                                ? DealingAnimationWidget(
                                    onComplete: () {
                                      if (mounted)
                                        setState(() => _isDealing = false);
                                    },
                                  )
                                : _buildTableCenter(state);
                          },
                        ),
                        const Spacer(),
                        _isDealing
                            ? const SizedBox(height: 80)
                            : _buildBottomArea(context, state),
                      ],
                    ),
                  ),
                ),
                // ── No manual redistribute button — fully automatic ──
                // ── Player Disconnect Countdown Red Circle in the Corner ──
                if (_hostDisconnectSeconds > 0)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.shade900.withOpacity(0.9),
                        border: Border.all(color: Colors.redAccent, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$_hostDisconnectSeconds',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                // ── Low Connection Popup Banner ──
                StreamBuilder<bool>(
                  stream: context
                      .read<OnlineBloc>()
                      .repository
                      .onConnectionChanged,
                  builder: (context, snapshot) {
                    final isConnected = snapshot.data ?? true;
                    if (isConnected) return const SizedBox.shrink();
                    return Positioned(
                      top: 12,
                      left: 20,
                      right: 20,
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(12),
                        color: const Color(0xFF1E1E2C).withOpacity(0.95),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.amber.shade600,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.amber,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Low Connection - Syncing state...',
                                  style: TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, OnlineState state) {
    // Always show turn indicator at top
    String turnLabel = '';
    bool isMyTurn = false;
    String? suit;
    bool isFirstTurn = false;
    bool isRoundDone = false;
    bool isWaiting = false;

    if (state is OnlinePlayerTurn) {
      isMyTurn = state.isMyTurn;
      turnLabel = isMyTurn ? 'Your Turn' : "${state.activePlayerName}'s Turn";
      suit = state.currentSuit?.name;
      isFirstTurn = state.isFirstTurn;
    } else if (state is OnlineWaitingForTurn) {
      turnLabel = "${state.activePlayerName}'s Turn";
      isWaiting = true;
      suit = state.currentRound?.suit.name;
    } else if (state is OnlineRoundCompleted) {
      isRoundDone = true;
      turnLabel = '${state.nextRoundLeaderName} leads next round';
    } else if (state is OnlinePunishmentNeeded) {
      turnLabel = 'Choose a card to punish';
      isMyTurn = true;
    } else {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        // ── Turn indicator pill ──
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: isMyTurn
                ? const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  )
                : isRoundDone
                ? LinearGradient(
                    colors: [Colors.green.shade800, Colors.green.shade600],
                  )
                : const LinearGradient(
                    colors: [Color(0xFF2A2A4A), Color(0xFF1A1A2E)],
                  ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: (isMyTurn ? Colors.orange : Colors.black).withValues(
                  alpha: 0.3,
                ),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isWaiting) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: const Color(0xFFC2C8A4),
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                Text(
                  isMyTurn
                      ? '🎯 '
                      : isRoundDone
                      ? '✅ '
                      : '👁 ',
                  style: const TextStyle(fontSize: 16),
                ),
              Text(
                turnLabel,
                style: TextStyle(
                  color: isMyTurn ? Colors.black87 : const Color(0xFFC2C8A4),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        // ── Suit indicator ──
        if (suit != null) ...[
          const SizedBox(height: 8),
          SuitIndicatorWidget(
            suit: state is OnlinePlayerTurn
                ? state.currentSuit
                : state is OnlineWaitingForTurn
                ? state.currentRound?.suit
                : null,
          ),
        ],
        // ── First turn notice ──
        if (isFirstTurn) ...[
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFC2C8A4),
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Text(
              '♠ Start with the Ace of Spades',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  // ─── Table Center ─────────────────────────────────────────────────────────

  Widget _buildTableCenter(OnlineState state) {
    if (state is OnlinePlayerTurn) {
      return TableCenterWidget(
        currentRound: state.currentRound,
        highestCard: state.highestCard,
        playerNames: state.playerNames,
      );
    }
    if (state is OnlineWaitingForTurn) {
      return TableCenterWidget(
        currentRound: state.currentRound,
        highestCard: null,
        playerNames: state.playerNames,
      );
    }
    if (state is OnlineRoundCompleted) {
      return TableCenterWidget(
        currentRound: state.completedRound,
        highestCard: null,
        playerNames: state.playerNames,
      );
    }
    return const SizedBox(height: 220);
  }

  // ─── Bottom Area ──────────────────────────────────────────────────────────

  Widget _buildBottomArea(BuildContext context, OnlineState state) {
    // Both host and guests see the same auto-advancing indicator
    if (state is OnlineRoundCompleted) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: const Color(0x61C2C8A4),
              ),
            ),
            SizedBox(width: 10),
            Text(
              'Starting next round…',
              style: TextStyle(color: const Color(0x61C2C8A4), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (state is OnlineWaitingForTurn) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: CategorizedHandWidget(
          cards: state.myHand,
          selectedCard: null,
          currentSuit: state.currentRound?.suit,
          isCardEnabled: (_) => false,
          onCardTap: (_) {},
        ),
      );
    }

    if (state is OnlinePlayerTurn) {
      // Only show interactive hand if it's actually YOUR turn
      if (!state.isMyTurn) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: CategorizedHandWidget(
            cards: state.myHand,
            selectedCard: null,
            currentSuit: state.currentRound?.suit,
            isCardEnabled: (_) => false,
            onCardTap: (_) {},
          ),
        );
      }
      return _buildMyTurnArea(context, state);
    }

    if (state is OnlinePunishmentNeeded) {
      return _buildPunishmentArea(context, state);
    }

    return const SizedBox(height: 48);
  }

  Widget _buildMyTurnArea(BuildContext context, OnlinePlayerTurn state) {
    final mustPunish =
        state.currentSuit != null &&
        !state.myHand.any((c) => c.suit == state.currentSuit);

    return Column(
      children: [
        if (_selectedCard != null) ...[
          if (mustPunish) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFC2C8A4),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
                border: Border.all(color: Colors.redAccent, width: 2),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text(
                    'No matching suit\nThis card will be given as punishment',
                    style: TextStyle(
                      color: Color(0xFFF2D87B),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                _submitMove(context, state, isPunishment: true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade900,
                foregroundColor: const Color(0xFFC2C8A4),
                side: const BorderSide(color: Colors.redAccent, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Give Punishment Card'),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: () => _submitMove(context, state, isPunishment: false),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A2C1A),
                foregroundColor: const Color(0xFFF2D87B),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 12,
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                side: const BorderSide(color: Color(0xFFD3AC47), width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Play Card'),
            ),
          ],
        ] else
          const SizedBox(height: 48),
        const SizedBox(height: 16),
        CategorizedHandWidget(
          key: ValueKey(state.activePlayerName),
          cards: state.myHand,
          selectedCard: _selectedCard,
          currentSuit: state.currentSuit,
          isCardEnabled: (_) => true,
          onCardTap: (card) {
            setState(() {
              _selectedCard = _selectedCard == card ? null : card;
            });
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  void _submitMove(
    BuildContext context,
    OnlinePlayerTurn state, {
    required bool isPunishment,
  }) {
    print(
      'RJDBG SUBMIT_MOVE: tapped, isPunishment=$isPunishment selectedCard=$_selectedCard',
    );
    if (_selectedCard == null) {
      print('RJDBG SUBMIT_MOVE: bailing — no card selected');
      return;
    }
    final card = _selectedCard!;
    setState(() => _selectedCard = null);

    final bloc = context.read<OnlineBloc>();
    print(
      'RJDBG SUBMIT_MOVE: isHost=${state.isHost} card=${card.rank.name} of ${card.suit.name}',
    );

    if (state.isHost) {
      // Host calls engine directly
      if (isPunishment) {
        bloc.add(OnlineGivePunishment(card));
      } else {
        bloc.add(OnlinePlayCard(card));
      }
      print('RJDBG SUBMIT_MOVE: dispatched host event');
    } else {
      // Guest submits via RTDB pendingAction
      final roomId = bloc.currentRoomId;
      final uid = bloc.myUid;
      print('RJDBG SUBMIT_MOVE: guest submitting, roomId=$roomId uid=$uid');
      if (roomId == null || uid == null) {
        print('RJDBG SUBMIT_MOVE: bailing — roomId or uid null, cannot submit');
        return;
      }
      bloc.repository
          .submitPendingAction(
            roomId: roomId,
            playerId: uid,
            type: isPunishment ? 'givePunishment' : 'playCard',
            cardSuit: card.suit.name,
            cardRank: card.rank.name,
          )
          .then((_) {
            print(
              'RJDBG SUBMIT_MOVE: submitPendingAction completed successfully',
            );
          })
          .catchError((e, st) {
            print('RJDBG SUBMIT_MOVE ERROR: $e');
            print('RJDBG SUBMIT_MOVE STACK: $st');
          });
    }
  }

  Widget _buildPunishmentArea(
    BuildContext context,
    OnlinePunishmentNeeded state,
  ) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFC2C8A4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
          ),
          child: Text(
            '⚠️  You must give a punishment card to ${state.receivingPlayerName}',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        CategorizedHandWidget(
          cards: state.myHand,
          selectedCard: _selectedCard,
          isCardEnabled: (_) => true,
          onCardTap: (card) {
            setState(() => _selectedCard = card);
            context.read<OnlineBloc>().add(OnlineGivePunishment(card));
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
