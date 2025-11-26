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

    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        if (value.isNotEmpty) {
          _navigateToSharePage(value.first.path);
        }
      },
      onError: (err) {
        debugPrint("Share Error: $err");
      },
    );

    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        _navigateToSharePage(value.first.path);
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
      theme: ThemeData(
        fontFamily: 'GeneralSans', // Applied globally
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const HomePage(),
    );
  }
}