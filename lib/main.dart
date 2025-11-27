import 'dart:async';
import 'package:flutter/material.dart';
import 'package:adobe/services/theme_service.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:adobe/ui/pages/home_page.dart';
import 'package:adobe/ui/pages/share_handler_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Removed await calls here to prevent startup freeze.
  // Initialization logic is now handled inside MyApp.
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
  
  // Controls the loading screen
  bool _isReady = false; 

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Load Theme (Wrapped in try-catch to be safe)
    try {
      await themeService.loadTheme();
    } catch (e) {
      debugPrint("⚠️ Theme load error (ignoring): $e");
    }

    // 2. Setup Sharing Intent Listener
    try {
      // Listen for shared files while app is running
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
          if (value.isNotEmpty) {
            _navigateToSharePage(value.first.path);
          }
        },
        onError: (err) {
          debugPrint("⚠️ Share stream error: $err");
        },
      );

      // Check if the app was launched via a share action (Cold Start)
      final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        _navigateToSharePage(initialMedia.first.path);
        ReceiveSharingIntent.instance.reset();
      }
    } catch (e) {
      debugPrint("⚠️ Share intent error: $e");
    }

    // Listen for theme changes to rebuild the UI dynamically
    themeService.addListener(_updateTheme);

    if (mounted) {
      setState(() {
        _isReady = true;
      });
    }
  }

  void _updateTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    try { _intentSub.cancel(); } catch (_) {}
    themeService.removeListener(_updateTheme);
    super.dispose();
  }

  void _navigateToSharePage(String sharedText) {
    // Wait for the frame to render before pushing the route
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ShareHandlerPage(sharedText: sharedText),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show a loading spinner until essential services are initialized
    if (!_isReady) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      navigatorKey: _navigatorKey,
      debugShowCheckedModeBanner: false,
      
      // Connect the ThemeService mode (Light / Dark / System)
      themeMode: themeService.mode, 

      // Light Theme Definition
      theme: ThemeData(
        fontFamily: 'GeneralSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue, 
          brightness: Brightness.light
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
        ),
      ),

      // Dark Theme Definition
      darkTheme: ThemeData(
        fontFamily: 'GeneralSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue, 
          brightness: Brightness.dark
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),

      home: const HomePage(),
    );
  }
}
