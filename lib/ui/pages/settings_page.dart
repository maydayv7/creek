import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/pages/image_analysis_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          "Settings",
          style: TextStyle(
            fontFamily: 'GeneralSans',
            color: Variables.textPrimary,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Variables.textPrimary),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text(
              "Test Image Analysis",
              style: TextStyle(
                fontFamily: 'GeneralSans',
                color: Variables.textPrimary,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: Variables.textSecondary,
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImageAnalysisPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
