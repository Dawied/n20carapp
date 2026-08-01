import 'package:flutter/material.dart';

/// A thumb-sized circular touch control for adjusting Speed in steps of 5.
/// Uses [PointerEvent.radiusMajor] and [PointerEvent.radiusMinor] for semi-pressure sensitive control.
class SpeedTouchControl extends StatefulWidget {
  final int currentSpeed;
  final int minSpeed;
  final int maxSpeed;
  final int step;
  final ValueChanged<int> onSpeedChanged;

  const SpeedTouchControl({
    super.key,
    required this.currentSpeed,
    this.minSpeed = 10,
    this.maxSpeed = 255,
    this.step = 5,
    required this.onSpeedChanged,
  });

  @override
  State<SpeedTouchControl> createState() => _SpeedTouchControlState();
}

class _SpeedTouchControlState extends State<SpeedTouchControl> {
  double _dragAccumulator = 0.0;
  bool _isTouched = false;

  void _handlePointerEvent(PointerEvent event) {
    // Extract touch contact area using radiusMajor and radiusMinor
    final double rMajor = event.radiusMajor;
    final double rMinor = event.radiusMinor;
    double radius = 0.0;

    if (rMajor > 0 || rMinor > 0) {
      radius = (rMajor > 0 && rMinor > 0)
          ? (rMajor + rMinor) / 2.0
          : (rMajor > 0 ? rMajor : rMinor);
    } else if (event.pressure > 0 && event.pressure != 1.0) {
      radius = event.pressure * 25.0;
    }

    if (radius > 0) {

      // Semi-pressure sensitivity: map contact radius (approx 6.0 to 32.0 px) to speed range
      const double minContactRadius = 6.0;
      const double maxContactRadius = 32.0;
      final double normalizedArea =
          ((radius - minContactRadius) / (maxContactRadius - minContactRadius))
              .clamp(0.0, 1.0);

      int targetSpeed =
          (widget.minSpeed + normalizedArea * (widget.maxSpeed - widget.minSpeed))
              .round();

      // Align to step increments (5)
      targetSpeed = (targetSpeed / widget.step).round() * widget.step;
      targetSpeed = targetSpeed.clamp(widget.minSpeed, widget.maxSpeed);

      if (targetSpeed != widget.currentSpeed) {
        widget.onSpeedChanged(targetSpeed);
      }
    }
  }

  void _updateSpeedByDelta(double dy) {
    // Dragging UP (negative dy) increases speed; dragging DOWN (positive dy) decreases speed.
    _dragAccumulator -= dy;
    const double pixelsPerStep = 6.0;

    if (_dragAccumulator.abs() >= pixelsPerStep) {
      final int steps = (_dragAccumulator / pixelsPerStep).truncate();
      _dragAccumulator -= steps * pixelsPerStep;

      final int newSpeed = (widget.currentSpeed + steps * widget.step).clamp(
        widget.minSpeed,
        widget.maxSpeed,
      );

      if (newSpeed != widget.currentSpeed) {
        widget.onSpeedChanged(newSpeed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF00E5FF) : const Color(0xFF00838F);
    final double fillPercentage = (widget.currentSpeed - widget.minSpeed) /
        (widget.maxSpeed - widget.minSpeed);

    return Listener(
      onPointerDown: (event) {
        setState(() => _isTouched = true);
        _handlePointerEvent(event);
      },
      onPointerMove: (event) {
        _handlePointerEvent(event);
      },
      onPointerUp: (_) => setState(() => _isTouched = false),
      onPointerCancel: (_) => setState(() => _isTouched = false),
      child: GestureDetector(
        onVerticalDragStart: (_) => _dragAccumulator = 0.0,
        onVerticalDragUpdate: (details) => _updateSpeedByDelta(details.delta.dy),
        onPanStart: (_) => _dragAccumulator = 0.0,
        onPanUpdate: (details) => _updateSpeedByDelta(details.delta.dy),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: _isTouched ? 0.95 : 0.85,
            ),
            border: Border.all(
              color: accentColor.withValues(alpha: _isTouched ? 0.9 : 0.6),
              width: _isTouched ? 3.5 : 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(
                  alpha: _isTouched ? 0.45 : 0.25,
                ),
                blurRadius: _isTouched ? 16 : 10,
                spreadRadius: _isTouched ? 3 : 1,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Circular progress indicator ring
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(3.0),
                  child: CircularProgressIndicator(
                    value: fillPercentage.clamp(0.0, 1.0),
                    strokeWidth: 3,
                    backgroundColor: Colors.transparent,
                    color: accentColor,
                  ),
                ),
              ),
              // "Speed" text and current speed in center
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Speed',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${widget.currentSpeed}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
