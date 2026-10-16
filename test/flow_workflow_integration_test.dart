import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'graph workflow connects, reconnects, deletes, undoes, and restores',
      (tester) async {
    final graph = FlowGraphController<String>(
      nodes: const [
        FlowNode<String>(
          id: 'source-a',
          position: Offset(20, 20),
          data: 'Source A',
          width: 100,
          height: 60,
          hasInput: false,
        ),
        FlowNode<String>(
          id: 'source-b',
          position: Offset(20, 140),
          data: 'Source B',
          width: 100,
          height: 60,
          hasInput: false,
        ),
        FlowNode<String>(
          id: 'target-c',
          position: Offset(300, 20),
          data: 'Target C',
          width: 100,
          height: 60,
          hasOutput: false,
        ),
        FlowNode<String>(
          id: 'target-d',
          position: Offset(300, 140),
          data: 'Target D',
          width: 100,
          height: 60,
          hasOutput: false,
        ),
      ],
    );
    final history = FlowHistoryController<String>();
    addTearDown(graph.dispose);
    addTearDown(history.dispose);

    FlowGraphState<String> state() =>
        FlowGraphState<String>(nodes: graph.nodes, edges: graph.edges);
    void commit(String label, FlowGraphState<String> before) {
      history.record(label: label, before: before, after: state());
    }

    final beforeCreate = state();
    graph.addNodes(const [
      FlowNode<String>(
        id: 'new-node',
        position: Offset(500, 80),
        data: 'New node',
        width: 100,
        height: 60,
      ),
    ]);
    commit('Create node', beforeCreate);

    final beforeConnect = state();
    final targetC = graph.getNode('target-c')!;
    final targetHandle = FlowGeometry.handleFor(
      targetC,
      null,
      FlowHandleType.target,
    )!;
    final connection = FlowGraphInteraction.connectionAt<String>(
      nodes: graph.nodes,
      edges: graph.edges,
      sourceId: 'source-a',
      sourceHandleId: null,
      point: FlowGeometry.handleAnchor(targetC, targetHandle),
      snapRadius: 1,
    );
    expect(connection, isNotNull);
    graph.addEdges([FlowGraphInteraction.createEdge(connection!, 'edge-1')]);
    commit('Connect nodes', beforeConnect);
    expect(graph.getNodeConnections('target-c'), hasLength(1));

    final beforeReconnect = state();
    final sourceB = graph.getNode('source-b')!;
    final sourceHandle = FlowGeometry.handleFor(
      sourceB,
      null,
      FlowHandleType.source,
    )!;
    final sourceConnection = FlowGraphInteraction.sourceConnectionAt<String>(
      nodes: graph.nodes,
      edges: graph.edges,
      targetId: 'target-c',
      targetHandleId: connection.targetHandleId,
      point: FlowGeometry.handleAnchor(sourceB, sourceHandle),
      snapRadius: 1,
      excludedEdgeId: 'edge-1',
    );
    expect(sourceConnection?.sourceId, 'source-b');
    graph.setEdges(FlowGraphInteraction.reconnectEdge(
      edges: graph.edges,
      edgeId: 'edge-1',
      connection: sourceConnection!,
    ));

    final targetD = graph.getNode('target-d')!;
    final targetDHandle = FlowGeometry.handleFor(
      targetD,
      null,
      FlowHandleType.target,
    )!;
    final targetConnection = FlowGraphInteraction.connectionAt<String>(
      nodes: graph.nodes,
      edges: graph.edges,
      sourceId: 'source-b',
      sourceHandleId: null,
      point: FlowGeometry.handleAnchor(targetD, targetDHandle),
      snapRadius: 1,
      excludedEdgeId: 'edge-1',
    );
    expect(targetConnection?.targetId, 'target-d');
    graph.setEdges(FlowGraphInteraction.reconnectEdge(
      edges: graph.edges,
      edgeId: 'edge-1',
      connection: targetConnection!,
    ));
    commit('Reconnect both ends', beforeReconnect);
    expect(graph.getEdge('edge-1')!.sourceId, 'source-b');
    expect(graph.getEdge('edge-1')!.targetId, 'target-d');

    final beforeDelete = state();
    final deletion = graph.deleteElements(nodeIds: const ['source-b']);
    commit('Delete connected node', beforeDelete);
    expect(deletion.deletedNodes.map((node) => node.id), ['source-b']);
    expect(deletion.deletedEdges.map((edge) => edge.id), ['edge-1']);
    expect(graph.edges, isEmpty);

    final undoState = history.undo();
    expect(undoState, isNotNull);
    graph.setGraph(nodes: undoState!.nodes, edges: undoState.edges);
    expect(graph.getEdge('edge-1')!.targetId, 'target-d');

    final encoded = graph
        .toSnapshot(const FlowViewport(x: 12, y: 24, zoom: 1.5))
        .toJson(encodeNodeData: (data) => data);
    final restored = FlowGraphSnapshot<String>.fromJson(
      encoded,
      decodeNodeData: (value) => value! as String,
    );
    graph.setGraph(nodes: restored.nodes, edges: restored.edges);
    expect(restored.viewport, const FlowViewport(x: 12, y: 24, zoom: 1.5));
    expect(graph.getEdge('edge-1')!.sourceId, 'source-b');
    expect(graph.getEdge('edge-1')!.targetId, 'target-d');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FFlowCanvas<String>(
          graphController: graph,
          nodeBuilder: (context, node, selected) => Text(node.data),
        ),
      ),
    ));
    expect(find.text('Source B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
