import 'package:flutter/material.dart';

import '../models/demo_node_data.dart';

class DemoNodePalette extends StatelessWidget {
  const DemoNodePalette({super.key, required this.onAdd});

  final ValueChanged<DemoNodeKind> onAdd;

  @override
  Widget build(BuildContext context) => Container(
        width: 232,
        decoration: const BoxDecoration(
          color: Color(0xFF11141C),
          border: Border(right: BorderSide(color: Color(0xFF252B37))),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('NODE LIBRARY',
                            style: TextStyle(
                              color: Color(0xFF9AA2B2),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                            )),
                        SizedBox(height: 5),
                        Text('Building blocks',
                            style: TextStyle(
                              color: Color(0xFFE6E8EF),
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            )),
                      ],
                    ),
                  ),
                  Icon(Icons.widgets_outlined,
                      size: 17, color: Color(0xFF8175D7)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFF252B37)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                children: [
                  for (final kind in DemoNodeKind.values)
                    _PaletteNode(kind: kind, onTap: () => onAdd(kind)),
                  const SizedBox(height: 18),
                  const _PaletteTip(),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 10, 18, 16),
              child: Text('FFlow SDK · interactive canvas demo',
                  style: TextStyle(color: Color(0xFF70798A), fontSize: 9)),
            ),
          ],
        ),
      );
}

class _PaletteNode extends StatelessWidget {
  const _PaletteNode({required this.kind, required this.onTap});

  final DemoNodeKind kind;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: const Color(0xFF171B25),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2B3240)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: kind.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(kind.icon, color: kind.accent, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kind.displayName,
                            style: const TextStyle(
                              color: Color(0xFFE4E6ED),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            )),
                        const SizedBox(height: 3),
                        Text(kind.paletteDescription,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF858D9D),
                              fontSize: 9,
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(width: 5),
                  const Icon(Icons.add_rounded,
                      color: Color(0xFF969EAE), size: 17),
                ],
              ),
            ),
          ),
        ),
      );
}

class _PaletteTip extends StatelessWidget {
  const _PaletteTip();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF191B2B),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF302D4B)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline_rounded,
                size: 15, color: Color(0xFFA99BFF)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Drag a node onto the canvas, then connect its handles.',
                style: TextStyle(
                  color: Color(0xFF9DA3B2),
                  fontSize: 9,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

extension on DemoNodeKind {
  String get paletteDescription => switch (this) {
        DemoNodeKind.trigger => 'Start a workflow',
        DemoNodeKind.ai => 'Transform or generate',
        DemoNodeKind.review => 'Request approval',
        DemoNodeKind.output => 'Send results onward',
      };
}
