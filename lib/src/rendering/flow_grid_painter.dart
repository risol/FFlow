import 'package:flutter/material.dart';

enum FlowBackgroundVariant { dots, lines, cross }

class FlowGridPainter extends CustomPainter {
  const FlowGridPainter({
    required this.color,
    required this.spacing,
    this.variant = FlowBackgroundVariant.dots,
  });

  final Color color;
  final double spacing;
  final FlowBackgroundVariant variant;

  @override
  void paint(Canvas canvas, Size size) {
    if (spacing <= 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final offset = spacing / 2;
    if (variant == FlowBackgroundVariant.lines) {
      for (var x = offset; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = offset; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
    } else {
      for (var x = offset; x < size.width; x += spacing) {
        for (var y = offset; y < size.height; y += spacing) {
          if (variant == FlowBackgroundVariant.dots) {
            canvas.drawCircle(Offset(x, y), 1, paint);
          } else {
            const length = 2.5;
            canvas.drawLine(
                Offset(x - length, y), Offset(x + length, y), paint);
            canvas.drawLine(
                Offset(x, y - length), Offset(x, y + length), paint);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant FlowGridPainter oldDelegate) =>
      color != oldDelegate.color ||
      spacing != oldDelegate.spacing ||
      variant != oldDelegate.variant;
}

/// Reusable canvas background that can be composed outside [FFlowCanvas].
class FFlowBackground extends StatelessWidget {
  const FFlowBackground({
    super.key,
    this.color = const Color(0xFF272D39),
    this.spacing = 24,
    this.variant = FlowBackgroundVariant.dots,
  });

  final Color color;
  final double spacing;
  final FlowBackgroundVariant variant;

  @override
  Widget build(BuildContext context) => CustomPaint(
      painter:
          FlowGridPainter(color: color, spacing: spacing, variant: variant));
}
