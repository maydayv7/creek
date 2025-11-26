// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adobe/services/theme_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:adobe/ui/pages/home_page.dart';
import 'package:adobe/ui/pages/share_handler_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeService.loadTheme();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _intentSub;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // 1. LISTEN: App is running in memory
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          // The URL, Text, or file path is inside the 'path' property
          _navigateToSharePage(value.first.path);
        }
      },
      onError: (err) {
        debugPrint("Share Error: $err");
      },
    );

    // 2. LISTEN: App is closed and opened via Share
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        _navigateToSharePage(value.first.path);

        // Optional: Clear the intent so it doesn't re-trigger on reload
        ReceiveSharingIntent.instance.reset();
      }
    });

    themeService.addListener(_updateTheme);
  }

  void _updateTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _intentSub.cancel();
    themeService.removeListener(_updateTheme);
    super.dispose();
  }

  void _navigateToSharePage(String sharedText) {
    // Navigate to the Share Handler Page
    // Use a microtask to ensure the navigator is ready
    Future.delayed(Duration.zero, () {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ShareHandlerPage(sharedText: sharedText),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Local Pinterest',
      
      // 1. Light Theme
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple, 
          brightness: Brightness.light
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        cardColor: Colors.grey[100], // Light gray cards
      ),

      // 2. Dark Theme
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple, 
          brightness: Brightness.dark
        ),
        scaffoldBackgroundColor: const Color(0xFF121212), // Dark background
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E), // Dark gray cards
      ),

      // 3. Mode Switcher
      themeMode: themeService.mode,
      
      home: const HomePage(),
    );
  }
}
