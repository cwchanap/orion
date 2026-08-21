import 'package:flutter/material.dart';

import 'game/ui/orion_game_page.dart';
import 'game/ui/orion_ui_theme.dart';

void main() {
  runApp(const OrionApp());
}

class OrionApp extends StatelessWidget {
  const OrionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Orion',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF31E6A1),
          brightness: Brightness.dark,
        ),
        extensions: const [OrionUiTheme.dark],
        useMaterial3: true,
      ),
      home: const OrionGamePage(),
    );
  }
}
