import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:creekui/services/project_service.dart';
import 'package:creekui/ui/styles/variables.dart';
import 'package:creekui/ui/widgets/text_field.dart';
import 'package:creekui/ui/widgets/primary_button.dart';
import 'project_detail_page.dart';

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
  final ProjectService _projectService = ProjectService();
  final _projectNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _problemController = TextEditingController();
  final _goalController = TextEditingController();
  final _whereWillAppearController = TextEditingController();
  final _competitorInputController = TextEditingController();

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
    _whereWillAppearController.dispose();
    _competitorInputController.dispose();
    super.dispose();
  }

  Future<void> _handleFinish() async {
    // 1. Basic Validation
    if (_projectNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Project name is required')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. Prepare data
      final String title = _projectNameController.text.trim();
      final String description = _descriptionController.text.trim();

      // 3. Call service and capture new ID
      final int newId = await _projectService.createProject(
        title,
        description: description.isEmpty ? null : description,
      );

      // 4. Navigate to ProjectDetailPage
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ProjectDetailPage(projectId: newId),
          ),
        );
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addCompetitorBrand() {
    final brandName = _competitorInputController.text.trim();
    if (brandName.isNotEmpty) {
      final initial = brandName[0].toUpperCase();
      setState(() {
        _competitorBrands.add({'name': brandName, 'initial': initial});
        _competitorInputController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Variables.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Back Button
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios,
                      size: 24,
                      color: Variables.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Icon
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E7FF),
                        borderRadius: BorderRadius.circular(1000),
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/painting-ai-line.svg',
                          width: 24,
                          height: 24,
                          colorFilter: const ColorFilter.mode(
                            Color(0xFF7C86FF),
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Define Your Brand', style: Variables.headerStyle),
                    const SizedBox(height: 4),
                    Text(
                      'Answer a few quick questions to help us craft your unique style guide.',
                      style: Variables.captionStyle.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    CommonTextField(
                      label: 'Project Name',
                      hintText: 'Enter project name',
                      controller: _projectNameController,
                      isRequired: true,
                    ),
                    const SizedBox(height: 16),
                    CommonTextField(
                      label: 'What do you want & who is it for.',
                      hintText: 'Describe your work and your audience.',
                      controller: _descriptionController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    CommonTextField(
                      label: 'What problem you solve.',
                      hintText: 'Explain the main issue your brand addresses.',
                      controller: _problemController,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    CommonTextField(
                      label: 'Long-term goal for the brand.',
                      hintText: 'E.g. - Improving food availability...',
                      controller: _goalController,
                    ),
                    const SizedBox(height: 32),
                    _buildKeywordsSection(),
                    const SizedBox(height: 32),
                    _buildCompetitorBrandsSection(),
                    const SizedBox(height: 32),
                    CommonTextField(
                      label: 'Where will the brand appear',
                      hintText: 'Banners, Posters, Instagram..',
                      controller: _whereWillAppearController,
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // Bottom Button
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        decoration: BoxDecoration(
          color: Variables.background,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: PrimaryButton(
            text: 'Create Project',
            isLoading: _isLoading,
            onPressed: _handleFinish,
            iconPath: 'assets/icons/generate_icon.svg',
          ),
        ),
      ),
    );
  }

  Widget _buildKeywordsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '2-3 vibe keywords',
              style: Variables.bodyStyle.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              '*',
              style: Variables.bodyStyle.copyWith(
                color: const Color(0xFF4F39F6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final keyword in _keywords)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      keyword,
                      style: Variables.captionStyle.copyWith(
                        fontSize: 12,
                        color: Variables.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _keywords.remove(keyword)),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: Variables.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            GestureDetector(
              onTap: _showAddKeywordDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Variables.borderSubtle),
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add More',
                      style: Variables.captionStyle.copyWith(
                        fontSize: 12,
                        color: Variables.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.add, size: 14, color: Variables.textPrimary),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompetitorBrandsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '2-3 reference/competitor brands.',
              style: Variables.bodyStyle.copyWith(fontWeight: FontWeight.w500),
            ),
            Text(
              '*',
              style: Variables.bodyStyle.copyWith(
                color: const Color(0xFF4F39F6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        CommonTextField(
          label: '',
          hintText: 'Type the name of brands here...',
          controller: _competitorInputController,
          onSubmitted: (_) => _addCompetitorBrand(),
        ),
        if (_competitorBrands.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _competitorBrands.length,
              itemBuilder: (context, index) {
                final brand = _competitorBrands[index];
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Variables.surfaceSubtle,
                    border: Border.all(color: Variables.borderSubtle),
                    borderRadius: BorderRadius.circular(64),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            brand['initial'] ?? '',
                            style: Variables.captionStyle.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(brand['name'] ?? '', style: Variables.bodyStyle),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap:
                            () => setState(
                              () => _competitorBrands.removeAt(index),
                            ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: Variables.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
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
                  if (val.isNotEmpty && !_keywords.contains(val))
                    setState(() => _keywords.add(val));
                  Navigator.pop(context);
                },
                child: const Text('Add'),
              ),
            ],
          ),
    );
  }
}
