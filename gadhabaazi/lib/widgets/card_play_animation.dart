import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/card_model.dart';
import 'card_widget.dart';

/// Overlay widget that plays the boomerang-curve card play animation.
/// Render it as the topmost child in a Stack.
class CardPlayAnimationOverlay extends StatefulWidget {
  final GlobalKey tableKey;
  final GlobalKey handKey;

  const CardPlayAnimationOverlay({
    super.key,
    required this.tableKey,
    required this.handKey,
  });

  @override
  State<CardPlayAnimationOverlay> createState() =>
      CardPlayAnimationOverlayState();
}

class CardPlayAnimationOverlayState
    extends State<CardPlayAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  PlayingCard? _card;
  bool _isPunishment = false;
  VoidCallback? _onComplete;

  // Animation values computed on play
  Offset _start = Offset.zero;
  Offset _control1 = Offset.zero;
  Offset _control2 = Offset.zero;
  Offset _end = Offset.zero;

  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _controller.addListener(() => setState(() {}));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _animating = false);
        _onComplete?.call();
        _controller.reset();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Call this to trigger the animation.
  void play({
    required PlayingCard card,
    required bool isPunishment,
    required VoidCallback onComplete,
  }) {
    if (_animating) return;

    // Locate hand area on screen
    Offset startOffset = const Offset(0, 0);
    if (widget.handKey.currentContext != null) {
      final handBox =
          widget.handKey.currentContext!.findRenderObject() as RenderBox?;
      if (handBox != null) {
        startOffset = handBox.localToGlobal(
          Offset(handBox.size.width * 0.5, handBox.size.height * 0.3),
        );
      }
    }

    // Locate table center on screen
    Offset endOffset = Offset(
      MediaQuery.of(context).size.width / 2,
      MediaQuery.of(context).size.height * 0.4,
    );
    if (widget.tableKey.currentContext != null) {
      final tableBox =
          widget.tableKey.currentContext!.findRenderObject() as RenderBox?;
      if (tableBox != null) {
        endOffset = tableBox.localToGlobal(
          Offset(tableBox.size.width / 2, tableBox.size.height / 2),
        );
      }
    }

    // Boomerang curve: control points arc left like a 6→9→12 clock sweep
    final double leftBulge = math.min(startOffset.dx, endOffset.dx) - 80;

    setState(() {
      _card = card;
      _isPunishment = isPunishment;
      _onComplete = onComplete;
      _start = startOffset;
      _control1 = Offset(leftBulge, startOffset.dy - 60);
      _control2 = Offset(leftBulge, endOffset.dy + 60);
      _end = endOffset;
      _animating = true;
    });

    _controller.forward(from: 0);
  }

  Offset _cubicBezier(double t) {
    final double u = 1 - t;
    return _start * (u * u * u) +
        _control1 * (3 * u * u * t) +
        _control2 * (3 * u * t * t) +
        _end * (t * t * t);
  }

  @override
  Widget build(BuildContext context) {
    if (!_animating || _card == null) return const SizedBox.shrink();

    final t = Curves.easeInOut.transform(_controller.value);
    final pos = _cubicBezier(t);

    // Slight rotation as card arcs
    final angle = (math.pi * -0.25) * math.sin(math.pi * t);
    // Scale pulses slightly
    final scale = 1.0 + 0.1 * math.sin(math.pi * t);

    return Positioned(
      left: pos.dx - 35,
      top: pos.dy - 50,
      child: Transform.rotate(
        angle: angle,
        child: Transform.scale(
          scale: scale,
          child: CardWidget(
            card: _card,
            faceUp: !_isPunishment,
            scale: 1.0,
          ),
        ),
      ),
    );
  }
}

// ─── Remote card drop-in animation ────────────────────────────────────────────

/// Shows a card dropping from above, rotating 3 times, landing on the table.
/// Face-up for normal plays, face-down for punishment.
class RemoteCardDropAnimation extends StatefulWidget {
  final PlayingCard card;
  final bool isPunishment;
  final VoidCallback onComplete;

  const RemoteCardDropAnimation({
    super.key,
    required this.card,
    required this.isPunishment,
    required this.onComplete,
  });

  @override
  State<RemoteCardDropAnimation> createState() =>
      _RemoteCardDropAnimationState();
}

class _RemoteCardDropAnimationState extends State<RemoteCardDropAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        // Drop from top of screen to table center
        final dy = -400.0 * (1 - t);
        // 3 full rotations (6π)
        final angle = 6 * math.pi * t;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: child,
          ),
        );
      },
      child: CardWidget(
        card: widget.card,
        faceUp: !widget.isPunishment,
        scale: 1.1,
      ),
    );
  }
}
