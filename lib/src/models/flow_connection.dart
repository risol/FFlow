/// The endpoints of a connection being created or moved.
class FlowConnection {
  const FlowConnection({
    required this.sourceId,
    required this.targetId,
    this.sourceHandleId,
    this.targetHandleId,
  });

  final String sourceId;
  final String targetId;
  final String? sourceHandleId;
  final String? targetHandleId;

  @override
  bool operator ==(Object other) =>
      other is FlowConnection &&
      other.sourceId == sourceId &&
      other.targetId == targetId &&
      other.sourceHandleId == sourceHandleId &&
      other.targetHandleId == targetHandleId;

  @override
  int get hashCode =>
      Object.hash(sourceId, sourceHandleId, targetId, targetHandleId);
}
