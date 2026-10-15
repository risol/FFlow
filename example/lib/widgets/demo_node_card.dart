import 'package:flutter/material.dart';
import 'package:fflow/fflow.dart';

import '../models/demo_node_data.dart';

class DemoNodeCard extends StatelessWidget {
  const DemoNodeCard({super.key, required this.node, required this.selected});

  final FlowNode<DemoNodeData> node;
  final bool selected;

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
              Icon(Icons.more_horiz_rounded,
                  size: 18, color: Colors.white.withValues(alpha: 0.42)),
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
