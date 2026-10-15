import 'package:flutter/material.dart';

class FlowPort extends StatelessWidget {
  const FlowPort({
    super.key,
    required this.isOutput,
    this.enabled = false,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  final bool isOutput;
  final bool enabled;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  @override
  Widget build(BuildContext context) {
    final color = isOutput ? const Color(0xFFAAA0FF) : const Color(0xFF8993A6);
    final port = Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: const Color(0xFF202633),
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 5)],
      ),
      child: Center(
        child: Container(
          width: 4,
          height: 4,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );

    if (!enabled) return IgnorePointer(child: port);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: SizedBox(width: 22, height: 22, child: Center(child: port)),
    );
  }
}
