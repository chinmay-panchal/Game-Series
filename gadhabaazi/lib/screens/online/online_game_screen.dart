import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/online/online_bloc.dart';
import '../../models/card_model.dart';
import '../../blocs/online/online_event.dart';
import '../../blocs/online/online_state.dart';

import '../../widgets/animated_background.dart';
import '../../widgets/premium_toast.dart';
import '../result/game_result_screen.dart';
import '../../widgets/suit_indicator_widget.dart';
import '../../widgets/categorized_hand_widget.dart';
import '../../widgets/table_center_widget.dart';
import '../../widgets/card_play_animation.dart';
import '../../engine/history/move_history.dart';
import '../game/widgets/dealing_animation_widget.dart';
import '../../services/audio_service.dart';
import '../home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/played_card.dart';

/// The main online game screen. Works for both host and guest.
class OnlineGameScreen extends StatefulWidget {
  final bool isRejoin;
  const OnlineGameScreen({super.key, this.isRejoin = false});

  @override
  State<OnlineGameScreen> createState() => _OnlineGameScreenState();
}

class _OnlineGameScreenState extends State<OnlineGameScreen>
    with WidgetsBindingObserver {
  PlayingCard? _selectedCard;
  String? _lastActivePlayer;
  String? _displayRoomCode;
  Timer? _roundCompleteTimer;
  bool _autoRedistributeDispatched = false;
  bool _isDealing = true;
  int _dealAmount = 24;

  // Animation keys
  final GlobalKey _tableKey = GlobalKey();

  // Remote card animation tracking
  List<PlayedCard> _lastPlayedCards = [];
  PlayingCard? _remoteDropCard;
  bool _remoteDropIsPunishment = false;
  bool _showRemoteDrop = false;
  bool _hasNavigatedToResult = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRoomCode();
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

  Future<void> _loadRoomCode() async {
    final blocCode = context.read<OnlineBloc>().currentRoomCode;
    if (blocCode != null && blocCode.isNotEmpty) {
      if (mounted) setState(() => _displayRoomCode = blocCode);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final savedCode = prefs.getString('active_online_room_code');
    if (mounted && savedCode != null) {
      setState(() => _displayRoomCode = savedCode);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roundCompleteTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      context.read<OnlineBloc>().add(OnlineLeaveRoom());
    } else if (state == AppLifecycleState.resumed) {
      context.read<OnlineBloc>().add(OnlineReassertPresence());
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnlineBloc, OnlineState>(
      listenWhen: (prev, curr) {
        if (curr is OnlineInitial) return true;
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
          if (curr.unendingLoopDetected) return true;
          return _lastActivePlayer != curr.activePlayerName;
        }
        return false;
      },
      listener: (context, state) {
        if (state is OnlineInitial) {
          _roundCompleteTimer?.cancel();
          if (mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
            );
          }
          return;
        }
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
        }

        bool loopDetected = false;
        bool isHost = false;
        if (state is OnlinePlayerTurn) {
          loopDetected = state.unendingLoopDetected;
          isHost = state.isHost;
        } else if (state is OnlineWaitingForTurn) {
          loopDetected = state.unendingLoopDetected;
          isHost = state.isHost;
        }

        // ── Auto-redistribute when loop detected ──
        if (loopDetected && !_autoRedistributeDispatched) {
          _autoRedistributeDispatched = true;
          setState(() {
            _isDealing = true;
            _dealAmount = 10; // 5 cards each = 10 total visuals
          });
          PremiumToast.show(
            context,
            'Loop 5 Situation! — redistributing 5-5 cards to both players!',

            duration: const Duration(seconds: 4),
          );
          if (isHost) {
            context.read<OnlineBloc>().add(OnlineDistributeNewCards());
          }
          return;
        }

        // Reset flag once loop is resolved
        if (!loopDetected) {
          _autoRedistributeDispatched = false;
        }

        if (state is OnlinePlayerTurn) {
          _lastActivePlayer = state.activePlayerName;
          if (_lastActivePlayer != null) {
            PremiumToast.show(context, "${state.activePlayerName}'s Turn");
          }
          if (_selectedCard != null) setState(() => _selectedCard = null);

          // ── Remote card drop animation ──
          final currentPlayed = state.currentRound?.playedCards ?? [];
          if (!state.isMyTurn &&
              currentPlayed.length > _lastPlayedCards.length) {
            final newCard = currentPlayed.last;
            // Only show animation if the card was NOT played by us
            if (newCard.playerId != state.myEngineId) {
              final isPunishment =
                  state.currentRound?.punishmentCard == newCard.card;
              _lastPlayedCards = List.from(currentPlayed);
              setState(() {
                _remoteDropCard = newCard.card;
                _remoteDropIsPunishment = isPunishment;
                _showRemoteDrop = true;
              });
            } else {
              _lastPlayedCards = List.from(currentPlayed);
            }
          } else {
            _lastPlayedCards = List.from(currentPlayed);
          }
        } else if (state is OnlineWaitingForTurn) {
          _lastActivePlayer = state.activePlayerName;
          PremiumToast.show(context, "${state.activePlayerName}'s Turn");
          if (_selectedCard != null) setState(() => _selectedCard = null);

          // ── Remote card drop animation ──
          final currentPlayed = state.currentRound?.playedCards ?? [];
          if (currentPlayed.length > _lastPlayedCards.length) {
            final newCard = currentPlayed.last;
            // Only show animation if the card was NOT played by us
            if (newCard.playerId != state.myEngineId) {
              _lastPlayedCards = List.from(currentPlayed);
              setState(() {
                _remoteDropCard = newCard.card;
                _remoteDropIsPunishment = false;
                _showRemoteDrop = true;
              });
            } else {
              _lastPlayedCards = List.from(currentPlayed);
            }
          } else {
            _lastPlayedCards = List.from(currentPlayed);
          }
        } else if (state is OnlineGameFinished) {
          if (_hasNavigatedToResult) return;
          _hasNavigatedToResult = true;
          _roundCompleteTimer?.cancel();
          SharedPreferences.getInstance().then((prefs) {
            prefs.remove('active_online_room_id');
            prefs.remove('active_online_room_code');
            prefs.remove('active_online_player_name');
            prefs.remove('active_online_player_uid');
            prefs.remove('active_online_expires_at');
          });
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
            final hasWon = context.read<OnlineBloc>().isCurrentPlayerWon;
            return await _confirmExit(context, hasWon: hasWon);
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
                        AnimatedOpacity(
                          opacity: _isDealing ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 500),
                          child: _buildHeader(context, state),
                        ),
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
                                    totalCardsToDealVisual: _dealAmount,
                                    onComplete: () {
                                      if (mounted)
                                        setState(() => _isDealing = false);
                                    },
                                  )
                                : SizedBox(
                                    key: _tableKey,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        _buildTableCenter(state),
                                        if (_showRemoteDrop &&
                                            _remoteDropCard != null)
                                          RemoteCardDropAnimation(
                                            card: _remoteDropCard!,
                                            isPunishment:
                                                _remoteDropIsPunishment,
                                            onComplete: () {
                                              if (mounted)
                                                setState(
                                                  () => _showRemoteDrop = false,
                                                );
                                            },
                                          ),
                                      ],
                                    ),
                                  );
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
                // ── Minimal Room Code Chip at Top Right ──
                if (_displayRoomCode != null && _displayRoomCode!.isNotEmpty)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    right: 12,
                    child: Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _displayRoomCode!));
                          AudioService().playTapSound();
                          PremiumToast.show(context, 'Code $_displayRoomCode copied!');
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A2C1A).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD3AC47), width: 1.2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.35),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            _displayRoomCode!,
                            style: const TextStyle(
                              color: Color(0xFFF2D87B),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.0,
                              decoration: TextDecoration.none,
                            ),
                          ),
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
        punishmentCard: state.punishmentCard,
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

    if (state is OnlineWaitingForTurn) {
      if (state.myHand.isEmpty) {
        return _buildSpectatorArea(context);
      }
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
      if (state.myHand.isEmpty) {
        return _buildSpectatorArea(context);
      }
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

  Widget _buildSpectatorArea(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 24),
              SizedBox(width: 8),
              Text(
                'You Won! Spectating match',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'All your cards are over. You can watch the remaining players or exit to the main menu without any penalty.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFC2C8A4), fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.exit_to_app, size: 16, color: Color(0xFFFFD700)),
            label: const Text(
              'Exit to Main Menu',
              style: TextStyle(
                color: Color(0xFFFFD700),
                fontWeight: FontWeight.bold,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            onPressed: () => _confirmExit(context, hasWon: true),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmExit(BuildContext context, {required bool hasWon}) async {
    AudioService().playTapSound();
    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: hasWon ? const Color(0xFF4CAF50) : const Color(0xFFD32F2F),
            width: 1.5,
          ),
        ),
        title: Text(
          hasWon ? 'Exit to Main Menu?' : 'Forfeit Game?',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          hasWon
              ? 'You have already finished all your cards and won! You can leave safely without any penalty.'
              : 'You still have cards in your hand! If you exit now, you will forfeit and become the Gadha (Donkey)!',
          style: const TextStyle(color: Color(0xFFC2C8A4)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              hasWon ? 'Stay & Watch' : 'Keep Playing',
              style: const TextStyle(color: Color(0xFFC2C8A4)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: hasWon ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(hasWon ? 'Exit Game' : 'Leave (Become Gadha)'),
          ),
        ],
      ),
    );

    if (shouldExit == true && mounted) {
      final bloc = context.read<OnlineBloc>();
      if (hasWon && bloc.roomId != null && bloc.myUid != null) {
        await bloc.repository.markPlayerWon(bloc.roomId!, bloc.myUid!);
      }
      bloc.add(OnlineLeaveRoom());
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );
      return true;
    }
    return false;
  }

  Widget _buildMyTurnArea(BuildContext context, OnlinePlayerTurn state) {
    final mustPunish =
        state.currentSuit != null &&
        !state.myHand.any((c) => c.suit == state.currentSuit);

    return Column(
      children: [
        if (_selectedCard != null) ...[
          if (mustPunish) ...[
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
    if (_selectedCard == null) return;
    final card = _selectedCard!;

    if (!isPunishment &&
        state.currentSuit != null &&
        card.suit != state.currentSuit) {
      PremiumToast.show(
        context,
        'You must play a ${state.currentSuit!.name} card!',
        isError: true,
      );
      return;
    }

    setState(() => _selectedCard = null);

    final bloc = context.read<OnlineBloc>();
    if (state.isHost) {
      if (isPunishment) {
        bloc.add(OnlineGivePunishment(card));
      } else {
        bloc.add(OnlinePlayCard(card));
      }
    } else {
      final roomId = bloc.currentRoomId;
      final uid = bloc.myUid;
      if (roomId == null || uid == null) return;
      bloc.repository.submitPendingAction(
        roomId: roomId,
        playerId: uid,
        type: isPunishment ? 'givePunishment' : 'playCard',
        cardSuit: card.suit.name,
        cardRank: card.rank.name,
      );
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
