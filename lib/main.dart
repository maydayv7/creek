import 'dart:async';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:adobe/services/theme_service.dart';
import 'package:adobe/ui/pages/share_handler_page.dart';
import 'package:adobe/ui/pages/home_page.dart';
import 'package:adobe/services/analysis_queue_manager.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AnalysisQueueManager().processQueue();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _intentStreamSubscription;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    // 1. Load Theme
    try {
      await themeService.loadTheme();
    } catch (e) {
      debugPrint("Theme load error (ignoring): $e");
    }

    // 2. Setup Share Listeneer
    try {
      _intentStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              _handleShare(value.first.path);
            }
          }, onError: (err) => debugPrint("Share error: $err"));

      // 3. Cold Start
      ReceiveSharingIntent.instance.getInitialMedia().then((
        List<SharedMediaFile> value,
      ) {
        if (value.isNotEmpty) {
          _handleShare(value.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      });
    } catch (e) {
      debugPrint("Share intent error: $e");
    }

    themeService.addListener(_updateTheme);

    if (mounted) setState(() => _isReady = true);
  }

  Future<void> _handleShare(String content) async {
    final context = _navigatorKey.currentState?.overlay?.context;
    if (context == null) return;

    // 1. Determine destination (Files vs Moodboards)
    String shareDestination = 'moodboards'; // Default
    try {
      const platform = MethodChannel('com.example.adobe/methods');
      final result = await platform.invokeMethod<String>('getShareSource');
      if (result != null) shareDestination = result;
    } catch (e) {
      debugPrint("Error getting share source: $e");
    }

    // 2. Pass destination to the Handler Page
    _navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder:
            (_) => ShareHandlerPage(
              sharedText: content,
              destination: shareDestination, // Pass the destination here
            ),
      ),
    );
  }

  void _updateTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _intentStreamSubscription.cancel();
    themeService.removeListener(_updateTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

      // Theme Configuration
      // themeMode: themeService.mode,
      themeMode: ThemeMode.light,

      theme: ThemeData(
        fontFamily: 'GeneralSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      darkTheme: ThemeData(
        fontFamily: 'GeneralSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
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
