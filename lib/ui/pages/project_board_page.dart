import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:adobe/ui/styles/variables.dart';
import 'package:adobe/ui/widgets/top_bar.dart';
import 'package:adobe/ui/widgets/bottom_bar.dart';
import '../../data/models/project_model.dart';
import '../../data/models/image_model.dart';
import '../../data/repos/project_repo.dart';
import '../../data/repos/note_repo.dart';
import '../../data/repos/image_repo.dart';
import 'project_tag_page.dart';
import 'project_board_page_alternate.dart';
import 'image_save_page.dart';
import 'image_details_page.dart';
import '../widgets/image_context_menu.dart';

class ProjectBoardPage extends StatefulWidget {
  final int projectId;

  const ProjectBoardPage({super.key, required this.projectId});

  @override
  State<ProjectBoardPage> createState() => _ProjectBoardPageState();
}

class _ProjectBoardPageState extends State<ProjectBoardPage> {
  final _projectRepo = ProjectRepo();
  final _imageRepo = ImageRepo();
  final _noteRepo = NoteRepo();
  final ImagePicker _picker = ImagePicker();

  final GlobalKey<ProjectBoardPageAlternateState> _alternatePageKey =
      GlobalKey();

  ProjectModel? _currentProject;
  Map<String, List<ImageModel>> _categorizedImages = {};
  bool _isLoading = true;
  bool _showAlternateView = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    try {
      final project = await _projectRepo.getProjectById(widget.projectId);
      if (project != null) {
        if (mounted) {
          setState(() {
            _currentProject = project;
          });
          await _loadImagesForSelected();
        }
      }
    } catch (e) {
      debugPrint("Error loading board: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadImagesForSelected() async {
    if (_currentProject?.id == null) return;
    if (!_showAlternateView) {
      setState(() => _isLoading = true);

      try {
        final images = await _imageRepo.getImages(_currentProject!.id!);
        final Map<String, List<ImageModel>> tempMap = {};
        await Future.wait(
          images.map((img) async {
            final Set<String> distinctCategories = {...img.tags};
            // final notes = await _noteRepo.getNotesForImage(img.id);
            // for (var note in notes) {
            //   if (note.category.isNotEmpty) {
            //     distinctCategories.add(note.category);
            //   }
            // }
            if (distinctCategories.isEmpty) {
              tempMap.putIfAbsent('Uncategorized', () => []).add(img);
            } else {
              for (var category in distinctCategories) {
                final list = tempMap.putIfAbsent(category, () => []);
                if (!list.any((i) => i.id == img.id)) {
                  list.add(img);
                }
              }
            }
          }),
        );

        _categorizedImages = tempMap;
      } catch (e) {
        debugPrint("Error loading images and note categories: $e");
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onProjectChanged(ProjectModel newProject) {
    if (newProject.id != _currentProject?.id) {
      setState(() {
        _currentProject = newProject;
      });
      if (!_showAlternateView) {
        _loadImagesForSelected();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _alternatePageKey.currentState?.refreshData();
        });
      }
    }
  }

  Future<void> _pickAndRedirect() async {
    try {
      final List<XFile> pickedFiles = await _picker.pickMultiImage();

      if (pickedFiles.isNotEmpty && _currentProject != null) {
        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) => ImageSavePage(
                  imagePaths: pickedFiles.map((e) => e.path).toList(),
                  projectId: _currentProject!.id!,
                  projectName: _currentProject!.title,
                  isFromShare: false,
                ),
          ),
        ).then((_) {
          if (!_showAlternateView) {
            _loadImagesForSelected();
          } else {
            _alternatePageKey.currentState?.refreshData();
          }
        });
      }
    } catch (e) {
      debugPrint("Error picking images: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentProject == null) {
      return const Scaffold(
        backgroundColor: Variables.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Variables.background,
      appBar: TopBar(
        currentProjectId: _currentProject!.id!,
        onBack: () => Navigator.pop(context),
        onProjectChanged: _onProjectChanged,
        onSettingsPressed: () {},
        isAlternateView: _showAlternateView,
        onLayoutToggle: () {
          setState(() {
            _showAlternateView = !_showAlternateView;
            if (!_showAlternateView) _loadImagesForSelected();
          });
        },
      ),
      bottomNavigationBar: BottomBar(
        currentTab: BottomBarItem.moodboard,
        projectId: _currentProject!.id!,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndRedirect,
        backgroundColor: Variables.textPrimary,
        foregroundColor: Variables.background,
        child: const Icon(Icons.add_photo_alternate_outlined),
      ),
      body: Column(
        children: [
          Expanded(
            child:
                _showAlternateView
                    ? ProjectBoardPageAlternate(
                      key: _alternatePageKey,
                      projectId: _currentProject!.id!,
                    )
                    : _buildCategorizedView(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorizedView() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_categorizedImages.isEmpty) {
      return Center(
        child: Text(
          "No images found",
          style: Variables.bodyStyle.copyWith(color: Variables.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      itemCount: _categorizedImages.keys.length,
      itemBuilder: (context, index) {
        final category = _categorizedImages.keys.elementAt(index);
        final images = _categorizedImages[category]!;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          // Keep this clipping so the scrolling list cuts off cleanly at the border
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Variables.borderSubtle),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () {
                  if (_currentProject?.id != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => ProjectTagPage(
                              projectId: _currentProject!.id!,
                              tag: category,
                            ),
                      ),
                    );
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        category.toUpperCase(),
                        style: Variables.headerStyle.copyWith(
                          fontSize: 14,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: Variables.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 140,
                child: ListView.separated(
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, imgIndex) {
                    final image = images[imgIndex];
                    return ImageContextMenu(
                      image: image,
                      onImageDeleted: () => _loadImagesForSelected(),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (_) => ProjectTagPage(
                                    projectId: _currentProject!.id!,
                                    tag: category,
                                  ),
                            ),
                          );
                        },

                        child: Container(
                          width: 120,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: Variables.surfaceSubtle,
                            border: Border.all(color: Variables.borderSubtle),
                          ),
                          // FIX: Explicitly clip image to border radius
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(image.filePath),
                                  fit: BoxFit.cover,
                                  errorBuilder:
                                      (_, __, ___) => Container(
                                        color: Variables.surfaceSubtle,
                                        child: const Icon(
                                          Icons.broken_image,
                                          color: Variables.textDisabled,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
