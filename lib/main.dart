import 'dart:async';
import 'dart:io'; // Required for File handling
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:adobe/services/theme_service.dart';
import 'package:adobe/ui/pages/share_to_moodboard_page.dart'; // Share Page
import 'package:adobe/ui/pages/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late StreamSubscription _intentSub;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  // Controls the loading screen
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
      debugPrint("⚠️ Theme load error (ignoring): $e");
    }

    // 2. Setup Sharing Intent Listener
    try {
      // Listen for shared files while app is running
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
          if (value.isNotEmpty) {
            _showShareOptions(value);
          }
        },
        onError: (err) {
          debugPrint("⚠️ Share stream error: $err");
        },
      );

      // Check if the app was launched via a share action (Cold Start)
      final initialMedia =
          await ReceiveSharingIntent.instance.getInitialMedia();
      if (initialMedia.isNotEmpty) {
        _showShareOptions(initialMedia);
        // Important: Reset immediately to avoid re-triggering on reload
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

  // --- SHARE HANDLING LOGIC ---

  void _showShareOptions(List<SharedMediaFile> files) {
    // We use the navigator key to get context because 'context' might not be valid in async callbacks
    final context = _navigatorKey.currentState?.overlay?.context;

    // Safety check: ensure we have context and a file
    if (context == null || files.isEmpty) return;

    final File imageFile = File(files.first.path);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 10),
                child: Text(
                  "Save Image To...",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),

              // Option 1: Moodboard
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.dashboard_customize,
                    color: Colors.blueAccent,
                  ),
                ),
                title: const Text("Moodboard"),
                subtitle: const Text("Add to references & analysis"),
                onTap: () {
                  Navigator.pop(context); // Close Bottom Sheet

                  // Navigate to ShareToMoodboardPage
                  _navigatorKey.currentState?.push(
                    MaterialPageRoute(
                      builder:
                          (_) => ShareToMoodboardPage(imageFile: imageFile),
                    ),
                  );
                },
              ),

              // Option 2: Project Files
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.folder_copy,
                    color: Colors.orangeAccent,
                  ),
                ),
                title: const Text("Project Files"),
                subtitle: const Text("Add to canvas assets"),
                onTap: () {
                  Navigator.pop(context); // Close Bottom Sheet

                  // Feature Placeholder
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Files feature coming soon!")),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    try {
      _intentSub.cancel();
    } catch (_) {}
    themeService.removeListener(_updateTheme);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Loading Screen
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
      navigatorKey:
          _navigatorKey, // Critical for global navigation from Share Intent
      debugShowCheckedModeBanner: false,

      // Theme Configuration
      themeMode: themeService.mode,

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
