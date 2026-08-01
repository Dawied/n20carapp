import 'package:flutter/material.dart';

/// A thumb-sized circular touch control for adjusting Speed in steps of 5
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
    final accentColor = isDark ? const Color(0xFF00E5FF) : const Color(0xFF00838F);
    final double fillPercentage = (widget.currentSpeed - widget.minSpeed) /
        (widget.maxSpeed - widget.minSpeed);

    return GestureDetector(
      onVerticalDragStart: (_) => _dragAccumulator = 0.0,
      onVerticalDragUpdate: (details) => _updateSpeedByDelta(details.delta.dy),
      onPanStart: (_) => _dragAccumulator = 0.0,
      onPanUpdate: (details) => _updateSpeedByDelta(details.delta.dy),
      child: Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.85),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.6),
            width: 2.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.25),
              blurRadius: 10,
              spreadRadius: 1,
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
            // "Speed" text in center
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
    );
  }
}
