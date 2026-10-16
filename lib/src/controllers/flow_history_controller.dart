import 'package:flutter/foundation.dart';

import '../models/flow_graph_transaction.dart';

/// Bounded transaction history for undo and redo.
///
/// The canvas can group frequent pointer updates by calling
/// [beginTransaction] once and [commitTransaction] when the gesture ends.
class FlowHistoryController<T> extends ChangeNotifier {
  FlowHistoryController({this.maxEntries = 100}) : assert(maxEntries > 0);

  final int maxEntries;
  final List<FlowGraphTransaction<T>> _past = [];
  final List<FlowGraphTransaction<T>> _future = [];
  FlowGraphState<T>? _pendingBefore;
  String? _pendingLabel;
  int _nextTransactionId = 0;

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;
  bool get isRecording => _pendingBefore != null;
  int get undoCount => _past.length;
  int get redoCount => _future.length;
  FlowGraphTransaction<T>? get nextUndo => _past.lastOrNull;
  FlowGraphTransaction<T>? get nextRedo => _future.lastOrNull;

  void beginTransaction(String label, FlowGraphState<T> before) {
    if (isRecording) return;
    _pendingLabel = label;
    _pendingBefore = before;
  }

  FlowGraphTransaction<T>? commitTransaction(FlowGraphState<T> after) {
    final before = _pendingBefore;
    if (before == null) return null;
    final transaction =
        _createTransaction(_pendingLabel ?? 'Edit graph', before, after);
    _pendingBefore = null;
    _pendingLabel = null;
    if (_sameState(before, after)) return null;
    _push(transaction);
    return transaction;
  }

  void cancelTransaction() {
    _pendingBefore = null;
    _pendingLabel = null;
  }

  FlowGraphTransaction<T> record({
    required String label,
    required FlowGraphState<T> before,
    required FlowGraphState<T> after,
  }) {
    final transaction = _createTransaction(label, before, after);
    if (!_sameState(before, after)) _push(transaction);
    return transaction;
  }

  FlowGraphState<T>? undo() {
    if (_past.isEmpty) return null;
    final transaction = _past.removeLast();
    _future.add(transaction);
    notifyListeners();
    return transaction.before;
  }

  FlowGraphState<T>? redo() {
    if (_future.isEmpty) return null;
    final transaction = _future.removeLast();
    _past.add(transaction);
    notifyListeners();
    return transaction.after;
  }

  void clear() {
    _past.clear();
    _future.clear();
    cancelTransaction();
    notifyListeners();
  }

  void _push(FlowGraphTransaction<T> transaction) {
    _past.add(transaction);
    if (_past.length > maxEntries) _past.removeAt(0);
    _future.clear();
    notifyListeners();
  }

  FlowGraphTransaction<T> _createTransaction(
    String label,
    FlowGraphState<T> before,
    FlowGraphState<T> after,
  ) =>
      FlowGraphTransaction.between<T>(
        id: 'fflow-${_nextTransactionId++}',
        label: label,
        before: before,
        after: after,
      );

  bool _sameState(FlowGraphState<T> a, FlowGraphState<T> b) =>
      listEquals(a.nodes, b.nodes) &&
      listEquals(a.edges, b.edges) &&
      setEquals(a.selection.nodes, b.selection.nodes) &&
      setEquals(a.selection.edges, b.selection.edges);
}
