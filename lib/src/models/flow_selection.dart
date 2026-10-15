/// The currently selected nodes and edges in a canvas.
class FlowSelection {
  FlowSelection(
      {Iterable<String> nodes = const [], Iterable<String> edges = const []})
      : nodes = Set.unmodifiable(nodes),
        edges = Set.unmodifiable(edges);

  final Set<String> nodes;
  final Set<String> edges;

  bool get isEmpty => nodes.isEmpty && edges.isEmpty;
}
