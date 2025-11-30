import 'package:flutter/material.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:flutter_svg/flutter_svg.dart';
// Import your service here
import '../../services/project_service.dart';

class DefineBrandPage extends StatefulWidget {
  final String projectName;
  final String? projectDescription;

  const DefineBrandPage({
    super.key,
    this.projectDescription,
    required this.projectName,
  });
  @override
  State<DefineBrandPage> createState() => _DefineBrandPageState();
}

class _DefineBrandPageState extends State<DefineBrandPage> {
  // Service
  final ProjectService _projectService = ProjectService();

  // Controllers
  final _projectNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _problemController = TextEditingController();
  final _goalController = TextEditingController();
  // controllers for quick add dialogs
  final _whereWillAppearController = TextEditingController();

  // State
  bool _isLoading = false;
  final List<String> _keywords = ['Colour', 'Fonts', 'Composition'];
  final List<Map<String, String>> _competitorBrands = [
    {'name': 'Mcdonalds', 'initial': 'M'},
    {'name': 'The Good Folks', 'initial': 'G'},
  ];

  @override
  void initState() {
    super.initState();
    // Pre-fill description if passed from previous page
    if (widget.projectDescription != null) {
      _descriptionController.text = widget.projectDescription!;
    }
    // Pre-fill project name if provided
    _projectNameController.text = widget.projectName;
  }

  @override
  void dispose() {
    _projectNameController.dispose();
    _descriptionController.dispose();
    _problemController.dispose();
    _goalController.dispose();
    // audience controller removed; not used in this form
    // no controller for keywords or competitors (we use chip lists)
    _whereWillAppearController.dispose();
    super.dispose();
  }

  Future<void> _handleFinish() async {
    // 1. Basic Validation
    if (_projectNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project name is missing.')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 2. Prepare the data
      // Note: Your createProject method needs to be updated to accept
      // 'brandData' or these specific fields if you want to save them.
      final brandData = {
        'description': _descriptionController.text.trim(),
        'problem': _problemController.text.trim(),
        'goal': _goalController.text.trim(),
        'keywords': _keywords,
        'competitors': _competitorBrands.map((b) => b['name']).toList(),
        'appear': _whereWillAppearController.text.trim(),
      };

      // 3. Call the Service
      // Debug: log brandData while backend integration is pending
      debugPrint('BrandData: $brandData');
      await _projectService.createProject(
        _projectNameController.text.trim(),
        description:
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
        // TODO: Pass brandData here if your service supports it
        // brandData: brandData,
      );

      // 4. Success Handling
      if (mounted) {
        // Pop with 'true' to indicate success so previous page can reload if needed
        Navigator.pop(context, true);
      }
    } catch (e) {
      // 5. Error Handling
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating project: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.background,
      appBar: AppBar(
        backgroundColor: Variables.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Variables.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const SizedBox.shrink(),
        centerTitle: false,
        // no actions (Skip removed)
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // Header area with icon, title and subtitle
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(44),
                          ),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/icons/painting-ai-line.svg',
                              width: 22,
                              height: 22,
                              color: Variables.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Define Your Brand',
                                style: TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  color: Variables.textPrimary,
                                  height: 24 / 20,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                'Answer a few quick questions to help us craft your unique style guide.',
                                style: TextStyle(
                                  fontFamily: 'GeneralSans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Variables.textSecondary,
                                  height: 18 / 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader("Project Name*"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _projectNameController,
                      hintText: 'Project Name',
                    ),
                    const SizedBox(height: 18),
                    _buildSectionHeader("What do you want & who is it for"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _descriptionController,
                      hintText: "Describe your work and your audience.",
                      maxLines: 4,
                    ),
                    const SizedBox(height: 18),

                    _buildSectionHeader("What problem you solve"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _problemController,
                      hintText: "Explain the main issue your brand addresses.",
                      maxLines: 3,
                    ),
                    const SizedBox(height: 18),

                    _buildSectionHeader("Long-term goal for the brand"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _goalController,
                      hintText: "E.g - Improving food availability...",
                    ),
                    const SizedBox(height: 18),

                    _buildSectionHeader("2-3 vibe keywords*"),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final k in _keywords)
                          InputChip(
                            label: Text(k),
                            onDeleted:
                                () => setState(() => _keywords.remove(k)),
                          ),
                        ActionChip(
                          label: const Text('Add More +'),
                          onPressed: _showAddKeywordDialog,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    _buildSectionHeader("2-3 reference/competitor brands*"),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 56,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          final b = _competitorBrands[index];
                          return Chip(
                            label: Text(b['name'] ?? ''),
                            avatar: CircleAvatar(
                              child: Text(b['initial'] ?? ''),
                            ),
                            onDeleted:
                                () => setState(
                                  () => _competitorBrands.removeAt(index),
                                ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemCount: _competitorBrands.length,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _showAddCompetitorDialog,
                      child: const Text('Add more +'),
                    ),
                    const SizedBox(height: 18),

                    _buildSectionHeader("Where will the brand appear"),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _whereWillAppearController,
                      hintText: "Banners, Posters, Instagram...",
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Button
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleFinish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Variables.textPrimary, // Black
                    foregroundColor: Variables.textWhite, // White text
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child:
                      _isLoading
                          ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                          : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Create Project",
                                style: Variables.buttonTextStyle.copyWith(
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SvgPicture.asset(
                                'assets/icons/generate_icon.svg',
                                width: 18,
                                height: 18,
                                color: Variables.textWhite,
                              ),
                            ],
                          ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Variables.bodyStyle.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: Variables.textPrimary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA), // Light grey background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Variables.borderSubtle),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: Variables.bodyStyle,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: Variables.bodyStyle.copyWith(
            color: Variables.textDisabled,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  void _showAddKeywordDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Keyword'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'e.g., Minimal'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final val = controller.text.trim();
                  if (val.isNotEmpty && !_keywords.contains(val)) {
                    setState(() => _keywords.add(val));
                  }
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }

  void _showAddCompetitorDialog() {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Add Competitor'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Brand name'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final val = controller.text.trim();
                  if (val.isNotEmpty) {
                    final initial = val.isNotEmpty ? val[0].toUpperCase() : '';
                    setState(
                      () => _competitorBrands.add({
                        'name': val,
                        'initial': initial,
                      }),
                    );
                  }
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }
}
