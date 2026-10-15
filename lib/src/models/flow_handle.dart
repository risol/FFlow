/// Which end of a connection handle can start or receive an edge.
enum FlowHandleType { source, target }

/// A handle's position relative to its node.
enum FlowHandlePosition { left, right, top, bottom }

/// A named connection point on a node.
class FlowHandle {
  const FlowHandle({
    required this.id,
    required this.type,
    required this.position,
    this.offset = 0.5,
    this.connectable = true,
    this.connectableStart = true,
    this.connectableEnd = true,
    this.maxConnections,
  });

  final String id;
  final FlowHandleType type;
  final FlowHandlePosition position;

  /// Position along the selected side, from 0.0 to 1.0.
  final double offset;
  final bool connectable;
  final bool connectableStart;
  final bool connectableEnd;
  final int? maxConnections;
}
