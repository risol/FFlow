import 'flow_handle.dart';

/// The endpoints of a connection being created or moved.
class FlowConnection {
  const FlowConnection({
    required this.sourceId,
    required this.targetId,
    this.sourceHandleId,
    this.targetHandleId,
    this.targetHandleType = FlowHandleType.target,
  });

  final String sourceId;
  final String targetId;
  final String? sourceHandleId;
  final String? targetHandleId;

  /// Type of the handle on the edge's target endpoint. This is normally a
  /// target handle; loose connections can connect a source handle here.
  final FlowHandleType targetHandleType;

  @override
  bool operator ==(Object other) =>
      other is FlowConnection &&
      other.sourceId == sourceId &&
      other.targetId == targetId &&
      other.sourceHandleId == sourceHandleId &&
      other.targetHandleId == targetHandleId &&
      other.targetHandleType == targetHandleType;

  @override
  int get hashCode => Object.hash(
      sourceId, sourceHandleId, targetId, targetHandleId, targetHandleType);
}
