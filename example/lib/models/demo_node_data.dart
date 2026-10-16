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

  String get defaultTitle => switch (this) {
        DemoNodeKind.trigger => 'New workflow request',
        DemoNodeKind.ai => 'Process with AI',
        DemoNodeKind.review => 'Review and approve',
        DemoNodeKind.output => 'Send results',
      };

  String get defaultDescription => switch (this) {
        DemoNodeKind.trigger => 'Starts when a new request arrives',
        DemoNodeKind.ai => 'Transform the incoming information',
        DemoNodeKind.review => 'Approve the result before continuing',
        DemoNodeKind.output => 'Deliver the approved result',
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

  DemoNodeData copyWith({String? title, String? description}) => DemoNodeData(
        title: title ?? this.title,
        description: description ?? this.description,
        kind: kind,
      );

  Map<String, Object?> toJson() => {
        'title': title,
        'description': description,
        'kind': kind.name,
      };

  factory DemoNodeData.fromJson(Object? value) {
    final json = value! as Map<String, Object?>;
    return DemoNodeData(
      title: json['title'] as String? ?? 'Workflow step',
      description: json['description'] as String? ?? '',
      kind: DemoNodeKind.values.byName(json['kind'] as String? ?? 'ai'),
    );
  }
}
