import 'package:flutter/material.dart';

class DemoSubflowCard extends StatelessWidget {
  const DemoSubflowCard({
    super.key,
    required this.title,
    required this.childCount,
    required this.collapsed,
    required this.selected,
  });

  final String title;
  final int childCount;
  final bool collapsed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF9B8BFF).withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? const Color(0xFF9B8BFF).withValues(alpha: 0.9)
                : const Color(0xFF9B8BFF).withValues(alpha: 0.42),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  collapsed ? Icons.folder_rounded : Icons.folder_open_rounded,
                  size: 16,
                  color: const Color(0xFFB9ACFF),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE7E2FF),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$childCount steps',
                  style: const TextStyle(
                    color: Color(0xFF9B91C5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
