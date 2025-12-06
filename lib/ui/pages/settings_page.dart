import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/pages/image_analysis_page.dart';
import 'package:creekui/ui/widgets/primary_button.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = true;
  String _originalName = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    String name = prefs.getString('user_name') ?? 'Alex';
    if (name.trim().isEmpty) {
      name = 'Alex';
    }

    setState(() {
      _nameController.text = name;
      _originalName = name;
      _isLoading = false;
    });
  }

  Future<void> _saveUserName() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', newName);

    setState(() {
      _originalName = newName;
    });

    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasChanges = _nameController.text.trim() != _originalName;
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
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Profile Settings",
                      style: TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Variables.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // User Name Field
                    const Text(
                      "Your Name",
                      style: TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 14,
                        color: Variables.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      onChanged: (val) {
                        setState(
                          () {},
                        ); // Trigger rebuild to show/hide checkmark
                      },
                      decoration: InputDecoration(
                        hintText: "Enter your name",
                        hintStyle: TextStyle(
                          color: Variables.textSecondary.withValues(alpha: 0.5),
                        ),
                        filled: true,
                        fillColor: Variables.surfaceSubtle,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon:
                            hasChanges
                                ? IconButton(
                                  icon: const Icon(
                                    Icons.check,
                                    color: Variables.textPrimary,
                                  ),
                                  onPressed: _saveUserName,
                                  tooltip: 'Save Name',
                                )
                                : null,
                      ),
                      style: const TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 16,
                        color: Variables.textPrimary,
                      ),
                    ),

                    const Spacer(),

                    // Test Analysis
                    PrimaryButton(
                      text: "Test Image Analysis",
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ImageAnalysisPage(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
    );
  }
}
