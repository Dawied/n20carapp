import 'package:flutter/material.dart';

/// An oval capsule slider control styled like [VirtualJoystick].
/// Supports both integer and double values with configurable steps and labels.
class DSlider<T extends num> extends StatefulWidget {
  final T currentValue;
  final T minValue;
  final T maxValue;
  final T step;
  final String label;
  final String Function(T value) formatValue;
  final ValueChanged<T> onChanged;

  const DSlider({
    super.key,
    required this.currentValue,
    required this.minValue,
    required this.maxValue,
    required this.step,
    required this.label,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  State<DSlider<T>> createState() => _DSliderState<T>();
}

class _DSliderState<T extends num> extends State<DSlider<T>> {
  static const double _trackWidth = 64.0;
  static const double _trackHeight = 160.0;
  static const double _knobSize = 44.0;
  static const double _innerMargin = 12.0;

  void _handleTouch(Offset localPosition) {
    const double minY = _innerMargin;
    const double maxY = _trackHeight - _knobSize - _innerMargin;
    const double maxTravel = maxY - minY;

    final double clampedTop =
        (localPosition.dy - (_knobSize / 2.0)).clamp(minY, maxY);

    // 0.0 at bottom (minValue), 1.0 at top (maxValue)
    final double fraction = 1.0 - ((clampedTop - minY) / maxTravel);

    final double minD = widget.minValue.toDouble();
    final double maxD = widget.maxValue.toDouble();
    final double stepD = widget.step.toDouble();

    final double rawVal = minD + fraction * (maxD - minD);
    double snappedVal = (rawVal / stepD).round() * stepD;
    snappedVal = snappedVal.clamp(minD, maxD);

    if (T == int) {
      final int intVal = snappedVal.round();
      if (intVal != widget.currentValue) {
        widget.onChanged(intVal as T);
      }
    } else {
      final double doubleVal = double.parse(snappedVal.toStringAsFixed(1));
      if ((doubleVal - widget.currentValue.toDouble()).abs() > 0.01) {
        widget.onChanged(doubleVal as T);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF00E5FF) : const Color(0xFF00838F);

    final double minD = widget.minValue.toDouble();
    final double maxD = widget.maxValue.toDouble();
    final double fraction = (widget.currentValue.toDouble() - minD) / (maxD - minD);

    const double minY = _innerMargin;
    const double maxY = _trackHeight - _knobSize - _innerMargin;
    const double maxTravel = maxY - minY;
    final double knobTop = minY + (1.0 - fraction.clamp(0.0, 1.0)) * maxTravel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Display current value outside at the top
        Text(
          widget.formatValue(widget.currentValue),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: accentColor,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanDown: (details) => _handleTouch(details.localPosition),
          onPanUpdate: (details) => _handleTouch(details.localPosition),
          onVerticalDragUpdate: (details) => _handleTouch(details.localPosition),
          child: SizedBox(
            width: _trackWidth,
            height: _trackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // Outer Oval / Capsule Track (matching VirtualJoystick aesthetic)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(_trackWidth / 2.0),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.35),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.15),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                // Central track groove line
                Positioned(
                  top: 24,
                  bottom: 24,
                  child: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // Movable Thumb Knob with 6-dot drag handle
                Positioned(
                  top: knobTop,
                  left: (_trackWidth - _knobSize) / 2.0,
                  child: Container(
                    width: _knobSize,
                    height: _knobSize,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                        BoxShadow(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.drag_indicator,
                      color: Colors.black54,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Text label outside under the control
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

/// Convenience component for Speed control
class SpeedSlider extends StatelessWidget {
  final int currentSpeed;
  final int minSpeed;
  final int maxSpeed;
  final int step;
  final ValueChanged<int> onSpeedChanged;

  const SpeedSlider({
    super.key,
    required this.currentSpeed,
    this.minSpeed = 10,
    this.maxSpeed = 255,
    this.step = 5,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DSlider<int>(
      currentValue: currentSpeed,
      minValue: minSpeed,
      maxValue: maxSpeed,
      step: step,
      label: 'SPEED',
      formatValue: (val) => '$val',
      onChanged: onSpeedChanged,
    );
  }
}

/// Convenience component for Steering Strength control
class SteeringStrengthSlider extends StatelessWidget {
  final double currentSteering;
  final double minSteering;
  final double maxSteering;
  final double step;
  final ValueChanged<double> onSteeringChanged;

  const SteeringStrengthSlider({
    super.key,
    required this.currentSteering,
    this.minSteering = 0.1,
    this.maxSteering = 1.0,
    this.step = 0.1,
    required this.onSteeringChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DSlider<double>(
      currentValue: currentSteering,
      minValue: minSteering,
      maxValue: maxSteering,
      step: step,
      label: 'STEERING',
      formatValue: (val) => '${(val * 10).round()}',
      onChanged: onSteeringChanged,
    );
  }
}
