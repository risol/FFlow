import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import 'flow_extension_adapters.dart';

/// Direction used by [FlowLayeredLayoutEngine].
enum FlowLayoutDirection {
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop,
}

/// A dependency-free directed graph layout that places nodes in layers.
///
/// Strongly connected nodes are kept in the same layer, so cycles do not make
/// the layout loop forever. Child nodes are laid out in their parent's local
/// coordinate space and their parent is expanded when needed. Edges between
/// nested groups are assigned to the closest shared ancestor for layering.
class FlowLayeredLayoutEngine<T> implements FlowLayoutEngine<T> {
  const FlowLayeredLayoutEngine({
    this.direction = FlowLayoutDirection.leftToRight,
    this.nodeSpacing = 48,
    this.layerSpacing = 96,
    this.groupPadding = 32,
  })  : assert(nodeSpacing >= 0),
        assert(layerSpacing >= 0),
        assert(groupPadding >= 0);

  final FlowLayoutDirection direction;
  final double nodeSpacing;
  final double layerSpacing;
  final double groupPadding;

  @override
  FlowLayoutResult layout({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    Map<String, Object?> options = const {},
  }) {
    final resolvedDirection = _resolveDirection(options['direction']);
    final resolvedNodeSpacing =
        _resolveSpacing('nodeSpacing', options, nodeSpacing);
    final resolvedLayerSpacing =
        _resolveSpacing('layerSpacing', options, layerSpacing);
    final resolvedGroupPadding =
        _resolveSpacing('groupPadding', options, groupPadding);
    final nodesById = {for (final node in nodes) node.id: node};
    final layoutNodes = <FlowNode<T>>[];
    final parentById = <String, String?>{};

    for (final node in nodes) {
      if (node.hidden || _hasHiddenAncestor(node, nodesById)) continue;
      final parentId = _validParent(node, nodesById);
      layoutNodes.add(node);
      parentById[node.id] = parentId;
    }

    final childrenByParent = <String?, List<FlowNode<T>>>{};
    for (final node in layoutNodes) {
      childrenByParent.putIfAbsent(parentById[node.id], () => []).add(node);
    }

    final groups = <String?, _LayoutGroup<T>>{};
    _LayoutGroup<T> buildGroup(String? parentId) {
      final siblings = childrenByParent[parentId] ?? <FlowNode<T>>[];
      final childGroups = <String, _LayoutGroup<T>>{};
      final sizes = <String, Size>{};

      for (final node in siblings) {
        final childGroup = buildGroup(node.id);
        if (childGroup.nodes.isEmpty) continue;
        childGroups[node.id] = childGroup;
        sizes[node.id] = Size(
          math.max(
              node.width, childGroup.size.width + resolvedGroupPadding * 2),
          math.max(
              node.height, childGroup.size.height + resolvedGroupPadding * 2),
        );
      }

      final groupEdges = <(String, String)>[];
      final siblingIds = {for (final node in siblings) node.id};
      for (final edge in edges) {
        final sourceId = _directChildFor(
          edge.sourceId,
          parentId,
          parentById,
          nodesById,
        );
        final targetId = _directChildFor(
          edge.targetId,
          parentId,
          parentById,
          nodesById,
        );
        if (sourceId == null ||
            targetId == null ||
            sourceId == targetId ||
            !siblingIds.contains(sourceId) ||
            !siblingIds.contains(targetId)) {
          continue;
        }
        groupEdges.add((sourceId, targetId));
      }

      final positions = _arrangeGroup(
        siblings,
        groupEdges,
        sizes,
        direction: resolvedDirection,
        nodeSpacing: resolvedNodeSpacing,
        layerSpacing: resolvedLayerSpacing,
      );
      var maxRight = 0.0;
      var maxBottom = 0.0;
      for (final node in siblings) {
        final topLeft = positions[node.id]!;
        final size = sizes[node.id] ?? Size(node.width, node.height);
        maxRight = math.max(maxRight, topLeft.dx + size.width);
        maxBottom = math.max(maxBottom, topLeft.dy + size.height);
      }

      final group = _LayoutGroup<T>(
        nodes: siblings,
        positions: positions,
        sizes: sizes,
        children: childGroups,
        size: Size(maxRight, maxBottom),
      );
      groups[parentId] = group;
      return group;
    }

    final root = buildGroup(null);
    final positions = <String, Offset>{};
    final sizes = <String, Size>{};

    void writeGroup(_LayoutGroup<T> group, Offset origin) {
      for (final node in group.nodes) {
        final size = group.sizes[node.id] ?? Size(node.width, node.height);
        final topLeft = origin + group.positions[node.id]!;
        positions[node.id] = Offset(
          topLeft.dx + size.width * node.origin.dx,
          topLeft.dy + size.height * node.origin.dy,
        );
        if (size != Size(node.width, node.height)) sizes[node.id] = size;
        final childGroup = group.children[node.id];
        if (childGroup != null) {
          writeGroup(
            childGroup,
            topLeft + Offset(resolvedGroupPadding, resolvedGroupPadding),
          );
        }
      }
    }

    writeGroup(root, Offset.zero);
    return FlowLayoutResult(positions, sizes: sizes);
  }

  FlowLayoutDirection _resolveDirection(Object? value) {
    if (value == null) return direction;
    if (value is FlowLayoutDirection) return value;
    if (value is String) {
      for (final candidate in FlowLayoutDirection.values) {
        if (candidate.name == value) return candidate;
      }
    }
    throw ArgumentError.value(value, 'options[direction]');
  }

  double _resolveSpacing(
    String key,
    Map<String, Object?> options,
    double fallback,
  ) {
    final value = options[key];
    if (value == null) return fallback;
    if (value is num && value.isFinite && value >= 0) return value.toDouble();
    throw ArgumentError.value(value, 'options[$key]');
  }

  bool _hasHiddenAncestor(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodesById,
  ) {
    var parentId = node.parentId;
    final visited = <String>{node.id};
    while (parentId != null && visited.add(parentId)) {
      final parent = nodesById[parentId];
      if (parent == null) return false;
      if (parent.hidden || parent.collapsed) return true;
      parentId = parent.parentId;
    }
    return false;
  }

  String? _validParent(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodesById,
  ) {
    final parentId = node.parentId;
    if (parentId == null || !nodesById.containsKey(parentId)) return null;
    String? ancestorId = parentId;
    final visited = <String>{node.id};
    while (ancestorId != null) {
      if (!visited.add(ancestorId)) return null;
      ancestorId = nodesById[ancestorId]?.parentId;
    }
    return parentId;
  }

  String? _directChildFor(
    String nodeId,
    String? groupParentId,
    Map<String, String?> parentById,
    Map<String, FlowNode<T>> nodesById,
  ) {
    var currentId = nodeId;
    final visited = <String>{};
    while (visited.add(currentId)) {
      final parentId = parentById[currentId];
      if (parentId == groupParentId) return currentId;
      if (parentId == null) return groupParentId == null ? currentId : null;
      currentId = parentId;
      if (!nodesById.containsKey(currentId)) return null;
    }
    return null;
  }

  Map<String, Offset> _arrangeGroup(
    List<FlowNode<T>> nodes,
    List<(String, String)> edges,
    Map<String, Size> expandedSizes, {
    required FlowLayoutDirection direction,
    required double nodeSpacing,
    required double layerSpacing,
  }) {
    if (nodes.isEmpty) return const {};
    final indexById = {for (var i = 0; i < nodes.length; i++) nodes[i].id: i};
    final adjacency = {
      for (final node in nodes) node.id: <String>{},
    };
    for (final (source, target) in edges) {
      adjacency[source]?.add(target);
    }

    var nextIndex = 0;
    final indices = <String, int>{};
    final lowLinks = <String, int>{};
    final stack = <String>[];
    final onStack = <String>{};
    final components = <List<String>>[];

    void connect(String nodeId) {
      indices[nodeId] = nextIndex;
      lowLinks[nodeId] = nextIndex++;
      stack.add(nodeId);
      onStack.add(nodeId);
      for (final target in adjacency[nodeId]!) {
        if (!indices.containsKey(target)) {
          connect(target);
          lowLinks[nodeId] = math.min(lowLinks[nodeId]!, lowLinks[target]!);
        } else if (onStack.contains(target)) {
          lowLinks[nodeId] = math.min(lowLinks[nodeId]!, indices[target]!);
        }
      }
      if (lowLinks[nodeId] != indices[nodeId]) return;
      final component = <String>[];
      String member;
      do {
        member = stack.removeLast();
        onStack.remove(member);
        component.add(member);
      } while (member != nodeId);
      component.sort((a, b) => indexById[a]!.compareTo(indexById[b]!));
      components.add(component);
    }

    for (final node in nodes) {
      if (!indices.containsKey(node.id)) connect(node.id);
    }

    final componentByNode = <String, int>{};
    final componentOrder = <int>[];
    for (var i = 0; i < components.length; i++) {
      componentOrder.add(components[i].firstOrNull == null
          ? nodes.length
          : indexById[components[i].first]!);
      for (final nodeId in components[i]) {
        componentByNode[nodeId] = i;
      }
    }

    final componentEdges = {
      for (var i = 0; i < components.length; i++) i: <int>{},
    };
    final indegrees = List<int>.filled(components.length, 0);
    for (final source in nodes) {
      final sourceComponent = componentByNode[source.id]!;
      for (final target in adjacency[source.id]!) {
        final targetComponent = componentByNode[target]!;
        if (sourceComponent != targetComponent &&
            componentEdges[sourceComponent]!.add(targetComponent)) {
          indegrees[targetComponent]++;
        }
      }
    }

    final ready = SplayTreeSet<int>((a, b) {
      final order = componentOrder[a].compareTo(componentOrder[b]);
      return order == 0 ? a.compareTo(b) : order;
    });
    for (var i = 0; i < components.length; i++) {
      if (indegrees[i] == 0) ready.add(i);
    }
    final ranks = List<int>.filled(components.length, 0);
    while (ready.isNotEmpty) {
      final component = ready.first;
      ready.remove(component);
      for (final target in componentEdges[component]!) {
        ranks[target] = math.max(ranks[target], ranks[component] + 1);
        indegrees[target]--;
        if (indegrees[target] == 0) ready.add(target);
      }
    }

    final nodeById = {for (final node in nodes) node.id: node};
    final layers = <int, List<FlowNode<T>>>{};
    for (final node in nodes) {
      final rank = ranks[componentByNode[node.id]!];
      layers.putIfAbsent(rank, () => []).add(node);
    }
    final layerRanks = layers.keys.toList()..sort();
    double primarySize(Size size) =>
        _isHorizontal(direction) ? size.width : size.height;
    double crossSize(Size size) =>
        _isHorizontal(direction) ? size.height : size.width;
    Size sizeOf(FlowNode<T> node) =>
        expandedSizes[node.id] ?? Size(node.width, node.height);

    final layerPrimarySizes = <double>[];
    final layerCrossSizes = <double>[];
    for (final rank in layerRanks) {
      var maxPrimary = 0.0;
      var totalCross = 0.0;
      for (final node in layers[rank]!) {
        final size = sizeOf(node);
        maxPrimary = math.max(maxPrimary, primarySize(size));
        totalCross += crossSize(size);
      }
      totalCross += math.max(0, layers[rank]!.length - 1) * nodeSpacing;
      layerPrimarySizes.add(maxPrimary);
      layerCrossSizes.add(totalCross);
    }

    final totalPrimary = layerPrimarySizes.fold<double>(
          0,
          (total, value) => total + value,
        ) +
        math.max(0, layerRanks.length - 1) * layerSpacing;
    final maxCross = layerCrossSizes.fold<double>(0, math.max);
    final positions = <String, Offset>{};
    var primaryOffset = 0.0;
    for (var layerIndex = 0; layerIndex < layerRanks.length; layerIndex++) {
      final layer = layers[layerRanks[layerIndex]]!
        ..sort((a, b) => indexById[a.id]!.compareTo(indexById[b.id]!));
      var crossOffset = (maxCross - layerCrossSizes[layerIndex]) / 2;
      for (final node in layer) {
        final size = sizeOf(node);
        final primaryLength = primarySize(size);
        final crossLength = crossSize(size);
        final reverse = direction == FlowLayoutDirection.rightToLeft ||
            direction == FlowLayoutDirection.bottomToTop;
        final primaryPosition = reverse
            ? totalPrimary - primaryOffset - primaryLength
            : primaryOffset;
        positions[node.id] = _isHorizontal(direction)
            ? Offset(primaryPosition, crossOffset)
            : Offset(crossOffset, primaryPosition);
        crossOffset += crossLength + nodeSpacing;
      }
      primaryOffset += layerPrimarySizes[layerIndex] + layerSpacing;
    }
    assert(nodeById.length == positions.length);
    return positions;
  }

  bool _isHorizontal(FlowLayoutDirection direction) =>
      direction == FlowLayoutDirection.leftToRight ||
      direction == FlowLayoutDirection.rightToLeft;
}

class _LayoutGroup<T> {
  const _LayoutGroup({
    required this.nodes,
    required this.positions,
    required this.sizes,
    required this.children,
    required this.size,
  });

  final List<FlowNode<T>> nodes;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;
  final Map<String, _LayoutGroup<T>> children;
  final Size size;
}
