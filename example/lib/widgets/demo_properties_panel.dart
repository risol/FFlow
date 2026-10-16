import 'package:flutter/material.dart';
import 'package:fflow/fflow.dart';

import '../models/demo_node_data.dart';

class DemoPropertiesPanel extends StatefulWidget {
  const DemoPropertiesPanel({
    super.key,
    this.node,
    this.edge,
    this.sourceTitle,
    this.targetTitle,
    required this.onApplyNode,
    required this.onApplyEdge,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
  }) : assert(node != null || edge != null);

  final FlowNode<DemoNodeData>? node;
  final FlowEdge? edge;
  final String? sourceTitle;
  final String? targetTitle;
  final void Function(String title, String description) onApplyNode;
  final void Function(String? label, FlowEdgeType type) onApplyEdge;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  State<DemoPropertiesPanel> createState() => _DemoPropertiesPanelState();
}

class _DemoPropertiesPanelState extends State<DemoPropertiesPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _labelController;
  late FlowEdgeType _edgeType;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _descriptionController = TextEditingController();
    _labelController = TextEditingController();
    _syncFields();
  }

  @override
  void didUpdateWidget(covariant DemoPropertiesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldNode = oldWidget.node;
    final node = widget.node;
    final oldEdge = oldWidget.edge;
    final edge = widget.edge;
    if (oldNode?.id != node?.id ||
        oldNode?.data.title != node?.data.title ||
        oldNode?.data.description != node?.data.description ||
        oldEdge?.id != edge?.id ||
        oldEdge?.label != edge?.label ||
        oldEdge?.type != edge?.type) {
      _syncFields();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _syncFields() {
    _titleController.text = widget.node?.data.title ?? '';
    _descriptionController.text = widget.node?.data.description ?? '';
    _labelController.text = widget.edge?.label ?? '';
    _edgeType = widget.edge?.type ?? FlowEdgeType.bezier;
  }

  bool get _canApplyNode {
    final node = widget.node;
    return node != null &&
        (_titleController.text.trim() != node.data.title ||
            _descriptionController.text.trim() != node.data.description);
  }

  bool get _canApplyEdge {
    final edge = widget.edge;
    return edge != null &&
        (_labelController.text.trim() != (edge.label ?? '') ||
            _edgeType != edge.type);
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 264,
        constraints: const BoxConstraints(maxHeight: 570),
        decoration: BoxDecoration(
          color: const Color(0xF0191D27),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF353D4D)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x44000000),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _PanelHeader(
                node: widget.node,
                edge: widget.edge,
                onClose: widget.onClose,
              ),
              const SizedBox(height: 15),
              if (widget.node case final node?) ...[
                _FieldLabel('STEP NAME'),
                const SizedBox(height: 6),
                _EditorTextField(
                  controller: _titleController,
                  hintText: 'Name this step',
                  maxLines: 1,
                ),
                const SizedBox(height: 12),
                _FieldLabel('DESCRIPTION'),
                const SizedBox(height: 6),
                _EditorTextField(
                  controller: _descriptionController,
                  hintText: 'What does this step do?',
                  minLines: 3,
                  maxLines: 4,
                ),
                const SizedBox(height: 13),
                _InfoRow(label: 'TYPE', value: node.data.kind.displayName),
                const SizedBox(height: 7),
                _InfoRow(label: 'ID', value: node.id),
                const SizedBox(height: 15),
                _ApplyButton(
                  enabled: _canApplyNode,
                  onPressed: () => widget.onApplyNode(
                    _titleController.text.trim(),
                    _descriptionController.text.trim(),
                  ),
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryAction(
                        icon: Icons.copy_rounded,
                        label: 'Duplicate',
                        onPressed: widget.onDuplicate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SecondaryAction(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        danger: true,
                        onPressed: widget.onDelete,
                      ),
                    ),
                  ],
                ),
              ] else if (widget.edge case final edge?) ...[
                _InfoRow(
                  label: 'FROM',
                  value: widget.sourceTitle ?? edge.sourceId,
                ),
                const SizedBox(height: 6),
                _InfoRow(
                  label: 'TO',
                  value: widget.targetTitle ?? edge.targetId,
                ),
                const SizedBox(height: 14),
                _FieldLabel('CONNECTION LABEL'),
                const SizedBox(height: 6),
                _EditorTextField(
                  controller: _labelController,
                  hintText: 'Optional label',
                  maxLines: 1,
                ),
                const SizedBox(height: 12),
                _FieldLabel('ROUTING STYLE'),
                const SizedBox(height: 6),
                DropdownButtonFormField<FlowEdgeType>(
                  value: _edgeType,
                  decoration: _fieldDecoration(),
                  dropdownColor: const Color(0xFF202532),
                  items: [
                    for (final type in FlowEdgeType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(_edgeTypeName(type)),
                      ),
                  ],
                  onChanged: (type) {
                    if (type != null) setState(() => _edgeType = type);
                  },
                ),
                const SizedBox(height: 15),
                _ApplyButton(
                  enabled: _canApplyEdge,
                  onPressed: () => widget.onApplyEdge(
                    _labelController.text.trim().isEmpty
                        ? null
                        : _labelController.text.trim(),
                    _edgeType,
                  ),
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: _SecondaryAction(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete connection',
                    danger: true,
                    onPressed: widget.onDelete,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader(
      {required this.node, required this.edge, required this.onClose});

  final FlowNode<DemoNodeData>? node;
  final FlowEdge? edge;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accent = node?.data.kind.accent ?? const Color(0xFF9B8BFF);
    final icon = node?.data.kind.icon ?? Icons.account_tree_outlined;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(node == null ? 'CONNECTION' : 'NODE SETTINGS',
                  style: const TextStyle(
                    color: Color(0xFF9AA2B2),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  )),
              const SizedBox(height: 3),
              Text(
                node?.data.title ?? 'Edit edge',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE9EAF0),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Close properties',
          onPressed: onClose,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 16),
          color: const Color(0xFF929AAA),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
        color: Color(0xFF9AA2B2),
        fontSize: 8,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.75,
      ));
}

class _EditorTextField extends StatelessWidget {
  const _EditorTextField({
    required this.controller,
    required this.hintText,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hintText;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        minLines: minLines,
        maxLines: maxLines,
        style: const TextStyle(color: Color(0xFFE6E8EF), fontSize: 11),
        decoration: _fieldDecoration().copyWith(hintText: hintText),
      );
}

class _ApplyButton extends StatelessWidget {
  const _ApplyButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 34,
        child: FilledButton.icon(
          onPressed: enabled ? onPressed : null,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF8172E9),
            disabledBackgroundColor: const Color(0xFF343743),
            foregroundColor: Colors.white,
            disabledForegroundColor: const Color(0xFF858B99),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle:
                const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
          ),
          icon: const Icon(Icons.check_rounded, size: 14),
          label: const Text('Apply changes'),
        ),
      );
}

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor:
              danger ? const Color(0xFFE98C91) : const Color(0xFFB9C0CD),
          side: const BorderSide(color: Color(0xFF363E4C)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
        ),
        icon: Icon(icon, size: 13),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 42,
            child: Text(label,
                style: const TextStyle(
                  color: Color(0xFF778091),
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.55,
                )),
          ),
          Expanded(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB8BFCC),
                  fontSize: 10,
                )),
          ),
        ],
      );
}

InputDecoration _fieldDecoration() => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFF12151D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF353C4A)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF353C4A)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF8E80F0)),
      ),
      hintStyle: const TextStyle(color: Color(0xFF6E7788), fontSize: 10),
    );

String _edgeTypeName(FlowEdgeType type) => switch (type) {
      FlowEdgeType.bezier => 'Bezier',
      FlowEdgeType.straight => 'Straight',
      FlowEdgeType.step => 'Step',
      FlowEdgeType.smoothStep => 'Smooth step',
      FlowEdgeType.simpleBezier => 'Simple bezier',
    };
