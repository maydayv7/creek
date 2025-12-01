import 'package:flutter/material.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  final _whereWillAppearController = TextEditingController();
  final _competitorInputController = TextEditingController();

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
    _whereWillAppearController.dispose();
    _competitorInputController.dispose();
    super.dispose();
  }

  Future<void> _handleFinish() async {
    // 1. Basic Validation - only Project Name is required
    if (_projectNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Project name is required.')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 2. Prepare the data
      final brandData = {
        'description': _descriptionController.text.trim(),
        'problem': _problemController.text.trim(),
        'goal': _goalController.text.trim(),
        'keywords': _keywords,
        'competitors': _competitorBrands.map((b) => b['name']).toList(),
        'appear': _whereWillAppearController.text.trim(),
      };

      // 3. Call the Service
      debugPrint('BrandData: $brandData');
      await _projectService.createProject(
        _projectNameController.text.trim().isEmpty
            ? 'Untitled Project'
            : _projectNameController.text.trim(),
        description:
            _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
      );

      // 4. Success Handling
      if (mounted) {
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
      backgroundColor: const Color(0xFFFAFAFA),
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
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
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

                    // Title and Subtitle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const SizedBox(height: 4),
                        Text(
                          'Answer a few quick questions to help us craft your unique style guide.',
                          style: TextStyle(
                            fontFamily: 'GeneralSans',
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Variables.textSecondary,
                            height: 20 / 14,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    // Form Fields
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Project Name (required, first field)
                        _buildFormField(
                          label: 'Project Name',
                          hintText: 'Enter project name',
                          controller: _projectNameController,
                          required: true,
                        ),
                        const SizedBox(height: 16),

                        // What do you want & who is it for
                        _buildFormField(
                          label: 'What do you want & who is it for.',
                          hintText: 'Describe your work and your audience.',
                          controller: _descriptionController,
                          maxLines: 3,
                          required: false,
                        ),
                        const SizedBox(height: 16),

                        // What problem you solve
                        _buildFormField(
                          label: 'What problem you solve.',
                          hintText:
                              'Explain the main issue your brand addresses.',
                          controller: _problemController,
                          maxLines: 3,
                          required: false,
                        ),
                        const SizedBox(height: 16),

                        // Long-term goal
                        _buildFormField(
                          label: 'Long-term goal for the brand.',
                          hintText: 'E.g. - Improving food availability...',
                          controller: _goalController,
                          required: false,
                        ),
                        const SizedBox(height: 32),

                        // Keywords Section
                        _buildKeywordsSection(),

                        const SizedBox(height: 32),

                        // Competitor Brands Section
                        _buildCompetitorBrandsSection(),

                        const SizedBox(height: 32),

                        // Where will the brand appear
                        _buildFormField(
                          label: 'Where will the brand appear',
                          hintText: 'Banners, Posters, Instagram..',
                          controller: _whereWillAppearController,
                          required: false,
                        ),
                      ],
                    ),

                    const SizedBox(height: 100), // Space for bottom button
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
          color: const Color(0xFFFAFAFA),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: Variables.textPrimary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(112),
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
                            'Create Project',
                            style: TextStyle(
                              fontFamily: 'GeneralSans',
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          SvgPicture.asset(
                            'assets/icons/generate_icon.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required String hintText,
    required TextEditingController controller,
    int maxLines = 1,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Variables.textPrimary,
                height: 20 / 14,
              ),
            ),
            if (required)
              Text(
                '*',
                style: TextStyle(
                  fontFamily: 'GeneralSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF4F39F6),
                  height: 16 / 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE4E4E7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              fontFamily: 'GeneralSans',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Variables.textPrimary,
              height: 20 / 14,
            ),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Variables.textSecondary,
                height: 20 / 14,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
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
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Variables.textPrimary,
                height: 20 / 14,
              ),
            ),
            Text(
              '*',
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4F39F6),
                height: 16 / 12,
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
                      style: TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Variables.textPrimary,
                        height: 16 / 12,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _keywords.remove(keyword);
                        });
                      },
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
                  border: Border.all(color: const Color(0xFFE4E4E7), width: 1),
                  borderRadius: BorderRadius.circular(48),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Add More',
                      style: TextStyle(
                        fontFamily: 'GeneralSans',
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Variables.textPrimary,
                        height: 16 / 12,
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
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Variables.textPrimary,
                height: 20 / 14,
              ),
            ),
            Text(
              '*',
              style: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF4F39F6),
                height: 16 / 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFE4E4E7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _competitorInputController,
            onSubmitted: (_) => _addCompetitorBrand(),
            style: TextStyle(
              fontFamily: 'GeneralSans',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Variables.textPrimary,
              height: 20 / 14,
            ),
            decoration: InputDecoration(
              hintText: 'Type the name of brands here...',
              hintStyle: TextStyle(
                fontFamily: 'GeneralSans',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Variables.textSecondary,
                height: 20 / 14,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
          ),
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
                    color: const Color(0xFFFAFAFA),
                    border: Border.all(
                      color: const Color(0xFFE4E4E7),
                      width: 1,
                    ),
                    borderRadius: BorderRadius.circular(64),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            brand['initial'] ?? '',
                            style: TextStyle(
                              fontFamily: 'GeneralSans',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Variables.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        brand['name'] ?? '',
                        style: TextStyle(
                          fontFamily: 'GeneralSans',
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Variables.textSecondary,
                          height: 20 / 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _competitorBrands.removeAt(index);
                          });
                        },
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
                  if (val.isNotEmpty && !_keywords.contains(val)) {
                    setState(() {
                      _keywords.add(val);
                    });
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
