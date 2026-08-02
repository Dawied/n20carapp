import 'package:flutter/material.dart';

class VirtualJoystick extends StatefulWidget {
  final Function(double x, double y) onJoystickChanged;
  final VoidCallback onJoystickStop;

  const VirtualJoystick({
    super.key,
    required this.onJoystickChanged,
    required this.onJoystickStop,
  });

  @override
  State<VirtualJoystick> createState() => VirtualJoystickState();
}

class VirtualJoystickState extends State<VirtualJoystick> {
  Offset _dragPosition = Offset.zero;
  final double _joystickRadius = 60.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor =
        isDark ? const Color(0xFF00E5FF) : const Color(0xFF00838F);
    final trackBgColor =
        isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final knobGradient = isDark
        ? const [Color(0xFF00E5FF), Color(0xFF00B0FF)]
        : const [Color(0xFF00ACC1), Color(0xFF00838F)];
    final knobIconColor = isDark ? Colors.black54 : Colors.white;
    final ringShadowColor = isDark
        ? accentColor.withValues(alpha: 0.15)
        : Colors.black.withValues(alpha: 0.08);

    return GestureDetector(
      onPanUpdate: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final localOffset = renderBox.globalToLocal(details.globalPosition);
        final center = Offset(
          renderBox.size.width / 2,
          renderBox.size.height / 2,
        );
        Offset offset = localOffset - center;

        // Clamp offset to joystick radius
        if (offset.distance > _joystickRadius) {
          offset = Offset.fromDirection(offset.direction, _joystickRadius);
        }

        setState(() {
          _dragPosition = offset;
        });

        // Normalize values to -50 to 50
        double normalizedX = (offset.dx / _joystickRadius) * 50.0;
        double normalizedY = -(offset.dy / _joystickRadius) * 50.0;

        widget.onJoystickChanged(normalizedX, normalizedY);
      },
      onPanEnd: (_) {
        setState(() {
          _dragPosition = Offset.zero;
        });
        widget.onJoystickStop();
      },
      child: SizedBox(
        width: 140,
        height: 140,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Background Ring
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: trackBgColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accentColor.withValues(alpha: isDark ? 0.3 : 0.45),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ringShadowColor,
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
            // Center indicator
            Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black26,
                  shape: BoxShape.circle,
                ),
              ),
            ),
            // Joystick thumb
            Positioned(
              left: 70.0 + _dragPosition.dx - 25.0,
              top: 70.0 + _dragPosition.dy - 25.0,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: knobGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    // Floating Z-elevation shadow
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                      spreadRadius: 1,
                    ),
                    if (isDark)
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                  ],
                ),
                child: Icon(
                  Icons.drag_indicator,
                  color: knobIconColor,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );

  }
}
