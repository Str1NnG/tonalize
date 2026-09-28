// ARQUIVO ATUALIZADO: lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// MUDANÇA 1: Importamos a nova splash screen
import 'screens/splash_screen.dart';
import 'providers/theme_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const TonalizeApp(),
    ),
  );
}

class TonalizeApp extends StatelessWidget {
  const TonalizeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'Tonalize',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00AFFF),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00AFFF), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: themeProvider.themeMode,

      // MUDANÇA 2: A tela inicial agora é a SplashScreen
      home: const SplashScreen(),
    );
  }
}