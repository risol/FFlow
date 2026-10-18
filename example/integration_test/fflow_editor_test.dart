import 'dart:convert';

import 'package:fflow_example/main.dart' as app;
import 'package:fflow_example/widgets/demo_node_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Future<void> _openEditorAction(
  WidgetTester tester, {
  required String tooltip,
  required String compactMenuLabel,
}) async {
  final directButton = find.byTooltip(tooltip);
  if (directButton.evaluate().isNotEmpty) {
    await tester.tap(directButton);
  } else {
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(compactMenuLabel));
  }
  await tester.pumpAndSettle();
}

Future<void> _openMoreAction(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('More actions'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('editor adds, undoes, redoes, exports, and imports a workflow',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('Research workflow'), findsOneWidget);
    expect(find.text('4 steps'), findsOneWidget);
    expect(find.text('3 connections'), findsOneWidget);

    await tester.tap(find.text('Research workflow'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Quality workflow');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Quality workflow'), findsOneWidget);

    await tester.tap(find.byTooltip('Add node'));
    await tester.pumpAndSettle();
    expect(find.text('Add a workflow step'), findsOneWidget);
    await tester.tap(find.text('AI step').last);
    await tester.pumpAndSettle();
    expect(find.text('5 steps'), findsOneWidget);
    expect(find.text('Process with AI'), findsWidgets);

    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pumpAndSettle();
    expect(find.text('4 steps'), findsOneWidget);
    expect(find.text('Process with AI'), findsNothing);

    await tester.tap(find.byTooltip('Redo (Ctrl+Shift+Z)'));
    await tester.pumpAndSettle();
    expect(find.text('5 steps'), findsOneWidget);
    expect(find.text('Process with AI'), findsWidgets);

    await _openEditorAction(
      tester,
      tooltip: 'Export workflow JSON',
      compactMenuLabel: 'Export JSON',
    );
    final exportText = tester
        .widget<SelectableText>(
          find.byType(SelectableText),
        )
        .data!;
    final importedSnapshot = Map<String, Object?>.from(
      jsonDecode(exportText) as Map,
    )..['workflowName'] = 'Imported workflow';
    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await tester.pumpAndSettle();

    await _openEditorAction(
      tester,
      tooltip: 'Import workflow JSON',
      compactMenuLabel: 'Import JSON',
    );
    final importDialog = find.byType(AlertDialog).last;
    await tester.enterText(
      find.descendant(of: importDialog, matching: find.byType(TextField)),
      jsonEncode(importedSnapshot),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.text('Imported workflow'), findsOneWidget);
    expect(find.text('5 steps'), findsOneWidget);
    expect(find.text('3 connections'), findsOneWidget);
    expect(find.text('Process with AI'), findsWidgets);
  });

  testWidgets('selected nodes can be grouped, collapsed, and expanded',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summarize sources'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(find.text('Editorial review'));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    await _openMoreAction(tester, 'Group selected nodes');
    expect(find.text('Subflow'), findsWidgets);
    expect(find.text('Summarize sources'), findsOneWidget);
    expect(find.text('Editorial review'), findsOneWidget);

    await _openMoreAction(tester, 'Collapse group');
    expect(find.text('Summarize sources'), findsNothing);
    expect(find.text('Editorial review'), findsNothing);
    expect(find.text('2 steps'), findsOneWidget);

    await _openMoreAction(tester, 'Expand group');
    expect(find.text('Summarize sources'), findsOneWidget);
    expect(find.text('Editorial review'), findsOneWidget);
  });

  testWidgets('editor routes edges and runs both layout actions',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await _openMoreAction(tester, 'Route edges');
    expect(find.text('Connections routed'), findsOneWidget);

    await _openMoreAction(tester, 'Auto layout');
    expect(find.text('Auto layout complete'), findsOneWidget);

    await _openMoreAction(tester, 'Force layout');
    expect(find.text('Force layout complete'), findsOneWidget);

    await tester.tap(find.text('Run'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Workflow completed'), findsOneWidget);

    await tester.tap(find.text('Run'));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Run stopped'), findsOneWidget);
  });

  testWidgets('nodes can connect and use keyboard copy and paste',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.byType(DemoNodeCard), findsNWidgets(4));
    final ports = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == 'FlowPort',
    );
    expect(ports, findsNWidgets(6));
    final sourcePoint = tester.getCenter(ports.at(0));
    final targetPoint = tester.getCenter(ports.at(3));
    await tester.dragFrom(
      sourcePoint,
      targetPoint - sourcePoint,
    );
    await tester.pumpAndSettle();
    expect(find.text('4 connections'), findsOneWidget);

    await tester.tap(find.text('Summarize sources'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('5 steps'), findsOneWidget);
    expect(find.text('Summarize sources'), findsWidgets);
  });

  testWidgets('node properties, cascade delete, and invalid import are handled',
      (tester) async {
    app.main();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Summarize sources'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'Summarize references',
    );
    await tester.tap(find.text('Apply changes'));
    await tester.pumpAndSettle();
    expect(find.text('Summarize references'), findsWidgets);

    await tester.tap(find.byTooltip('Delete selection'));
    await tester.pumpAndSettle();
    expect(find.text('3 steps'), findsOneWidget);
    expect(find.text('1 connections'), findsOneWidget);

    await _openEditorAction(
      tester,
      tooltip: 'Import workflow JSON',
      compactMenuLabel: 'Import JSON',
    );
    final importDialog = find.byType(AlertDialog).last;
    await tester.enterText(
      find.descendant(of: importDialog, matching: find.byType(TextField)),
      '{invalid json',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not import workflow'), findsOneWidget);
    expect(find.text('3 steps'), findsOneWidget);
    expect(find.text('1 connections'), findsOneWidget);
  });
}
