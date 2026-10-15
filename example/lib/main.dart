import 'package:flutter/material.dart';

import 'screens/flow_editor_screen.dart';

void main() {
  runApp(const FFlowExampleApp());
}

class FFlowExampleApp extends StatelessWidget {
  const FFlowExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FFlow SDK example',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF0B0E14),
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF8B7CFF),
            secondary: Color(0xFF69D6C8),
            surface: Color(0xFF151923),
            onSurface: Color(0xFFF2F3F7),
          ),
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
        ),
        home: const FlowEditorScreen(),
      );
}
