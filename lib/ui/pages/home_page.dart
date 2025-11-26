import 'package:flutter/material.dart';
import 'package:adobe/ui/pages/board_list_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Directly return the BoardListPage, which has its own Scaffold and AppBar
    return const BoardListPage();
  }
}