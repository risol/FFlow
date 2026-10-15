import 'package:flutter/material.dart';

enum DemoNodeKind { trigger, ai, review, output }

extension DemoNodeKindPresentation on DemoNodeKind {
  String get kindLabel => switch (this) {
        DemoNodeKind.trigger => 'TRIGGER',
        DemoNodeKind.ai => 'AI STEP',
        DemoNodeKind.review => 'HUMAN REVIEW',
        DemoNodeKind.output => 'OUTPUT',
      };

  String get displayName => switch (this) {
        DemoNodeKind.trigger => 'Trigger',
        DemoNodeKind.ai => 'AI step',
        DemoNodeKind.review => 'Human review',
        DemoNodeKind.output => 'Output',
      };

  IconData get icon => switch (this) {
        DemoNodeKind.trigger => Icons.bolt_rounded,
        DemoNodeKind.ai => Icons.auto_awesome_rounded,
        DemoNodeKind.review => Icons.rate_review_outlined,
        DemoNodeKind.output => Icons.outbox_rounded,
      };

  Color get accent => switch (this) {
        DemoNodeKind.trigger => const Color(0xFF55C7B4),
        DemoNodeKind.ai => const Color(0xFF9B8BFF),
        DemoNodeKind.review => const Color(0xFFF2B66D),
        DemoNodeKind.output => const Color(0xFF76A9FF),
      };
}

class DemoNodeData {
  const DemoNodeData(
      {required this.title, required this.description, required this.kind});

  final String title;
  final String description;
  final DemoNodeKind kind;
}
