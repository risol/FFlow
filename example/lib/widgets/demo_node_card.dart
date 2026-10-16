import 'package:flutter/material.dart';
import 'package:fflow/fflow.dart';

import '../models/demo_node_data.dart';

class DemoNodeCard extends StatelessWidget {
  const DemoNodeCard({
    super.key,
    required this.node,
    required this.selected,
    required this.onDuplicate,
    required this.onDelete,
    this.running = false,
    this.completed = false,
  });

  final FlowNode<DemoNodeData> node;
  final bool selected;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final bool running;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final data = node.data;
    final accent = data.kind.accent;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF171B25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? accent.withValues(alpha: 0.95)
              : const Color(0xFF303747),
          width: selected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 24,
              offset: const Offset(0, 10)),
          if (running)
            BoxShadow(
                color: accent.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 1),
          if (selected)
            BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 18,
                spreadRadius: 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(data.kind.icon, size: 17, color: accent),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  data.kind.kindLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.15),
                ),
              ),
              if (running)
                SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.7,
                    color: accent,
                  ),
                )
              else if (completed)
                const Icon(Icons.check_circle_rounded,
                    size: 17, color: Color(0xFF5CC6A4))
              else
                PopupMenuButton<String>(
                  tooltip: 'Node actions',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  iconSize: 18,
                  icon: Icon(Icons.more_horiz_rounded,
                      color: Colors.white.withValues(alpha: 0.52)),
                  color: const Color(0xFF202532),
                  onSelected: (action) {
                    if (action == 'duplicate') onDuplicate();
                    if (action == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'duplicate',
                      child: _NodeMenuItem(
                        icon: Icons.copy_rounded,
                        label: 'Duplicate',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: _NodeMenuItem(
                        icon: Icons.delete_outline_rounded,
                        label: 'Delete',
                        danger: true,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 11),
          Text(data.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFFF1F2F6),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(data.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Color(0xFF8991A1), fontSize: 10.5, height: 1.2)),
        ],
      ),
    );
  }
}

class _NodeMenuItem extends StatelessWidget {
  const _NodeMenuItem({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon,
              size: 15,
              color:
                  danger ? const Color(0xFFE98C91) : const Color(0xFFB6BECC)),
          const SizedBox(width: 9),
          Text(label,
              style: TextStyle(
                color:
                    danger ? const Color(0xFFE98C91) : const Color(0xFFE2E5EC),
                fontSize: 11,
              )),
        ],
      );
}
