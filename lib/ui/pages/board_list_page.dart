import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/repos/board_repo.dart';
import '../../data/repos/board_category_repo.dart';
import '../../data/repos/board_image_repo.dart';
import '../../data/models/board_model.dart';
import '../../data/models/category_model.dart';
import 'board_detail_page.dart';
import 'image_analysis_page.dart';

class BoardListPage extends StatefulWidget {
  const BoardListPage({super.key});

  @override
  State<BoardListPage> createState() => _BoardListPageState();
}

class _BoardListPageState extends State<BoardListPage> {
  final _categoryRepo = BoardCategoryRepository();
  final _boardRepo = BoardRepository();
  final _boardImageRepo = BoardImageRepository();

  Map<BoardCategory, List<Board>> _categorizedBoards = {};
  Map<int, List<String>> _boardPreviews = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final categoriesRaw = await _categoryRepo.getAllCategories();
      final categories =
          categoriesRaw.map((e) => BoardCategory.fromMap(e)).toList();

      final Map<BoardCategory, List<Board>> newCategorizedBoards = {};
      final Map<int, List<String>> newPreviews = {};

      for (final category in categories) {
        final boardsRaw = await _categoryRepo.getBoardsByCategory(category.id);
        final boards = boardsRaw.map((e) => Board.fromMap(e)).toList();
        newCategorizedBoards[category] = boards;

        for (final board in boards) {
          final imagesRaw = await _boardImageRepo.getImagesOfBoard(board.id);
          final paths =
              imagesRaw.map((e) => e['filePath'] as String).take(5).toList();
          newPreviews[board.id] = paths;
        }
      }

      if (mounted) {
        setState(() {
          _categorizedBoards = newCategorizedBoards;
          _boardPreviews = newPreviews;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading boards: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createCategoryDialog() async {
    final nameController = TextEditingController();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text("Create Category"),
            content: TextField(
              controller: nameController,
              decoration: const InputDecoration(hintText: "Category Name"),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.isNotEmpty) {
                    await _categoryRepo.createCategory(nameController.text);
                    if (c.mounted) Navigator.pop(c);
                    _loadData();
                  }
                },
                child: const Text("Create"),
              ),
            ],
          ),
    );
  }

  Future<void> _createBoardDialog({BoardCategory? preSelectedCategory}) async {
    final nameController = TextEditingController();
    final categories = _categorizedBoards.keys.toList();
    BoardCategory? selectedCategory =
        preSelectedCategory ??
        (categories.isNotEmpty ? categories.first : null);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder:
          (c) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: const Text("Create New Board"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          hintText: "Board Name",
                        ),
                        autofocus: true,
                      ),
                      const SizedBox(height: 16),
                      if (categories.isNotEmpty)
                        DropdownButton<BoardCategory>(
                          value: selectedCategory,
                          isExpanded: true,
                          hint: const Text("Select Category"),
                          items:
                              categories
                                  .map(
                                    (cat) => DropdownMenuItem(
                                      value: cat,
                                      child: Text(cat.name),
                                    ),
                                  )
                                  .toList(),
                          onChanged:
                              (val) => setState(() => selectedCategory = val),
                        ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        if (nameController.text.isNotEmpty &&
                            selectedCategory != null) {
                          await _boardRepo.createBoard(
                            nameController.text,
                            categoryId: selectedCategory!.id,
                          );
                          if (c.mounted) Navigator.pop(c);
                          _loadData();
                        }
                      },
                      child: const Text("Create"),
                    ),
                  ],
                ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Cookie point",
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 24,
            fontFamily: 'GeneralSans',
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.hexagon_outlined, color: Colors.black),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImageAnalysisPage()),
              );
            },
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  // Header Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: const [
                              Text(
                                "Global",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'GeneralSans',
                                  color: Colors.black87,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.keyboard_arrow_down,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.splitscreen_outlined,
                          size: 24,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.grid_view,
                          size: 24,
                          color: Colors.black87,
                        ),
                      ],
                    ),
                  ),

                  // Main Content
                  Expanded(
                    child:
                        _categorizedBoards.isEmpty
                            ? Center(
                              child: ElevatedButton(
                                onPressed: _createCategoryDialog,
                                child: const Text("Create Your First Category"),
                              ),
                            )
                            : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 40),
                              itemCount: _categorizedBoards.length,
                              itemBuilder: (context, index) {
                                final category = _categorizedBoards.keys
                                    .elementAt(index);
                                final boards = _categorizedBoards[category]!;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Category Header
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        0,
                                        20,
                                        8,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              category.name,
                                              style: const TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w500,
                                                color: Color.fromARGB(
                                                  255,
                                                  38,
                                                  56,
                                                  255,
                                                ),
                                                fontFamily: 'GeneralSans',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (boards.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 20,
                                        ),
                                        child: GestureDetector(
                                          onTap:
                                              () => _createBoardDialog(
                                                preSelectedCategory: category,
                                              ),
                                          child: const Text(
                                            "+ Add Board",
                                            style: TextStyle(
                                              color: Colors.blue,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      ...boards.map(
                                        (board) => _buildBoardPreviewCard(
                                          board,
                                          category.name,
                                        ),
                                      ),

                                    const SizedBox(height: 12),
                                  ],
                                );
                              },
                            ),
                  ),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createCategoryDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBoardPreviewCard(Board board, String categoryName) {
    final previewImages = _boardPreviews[board.id] ?? [];

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BoardDetailPage(board: board)),
        ).then((_) => _loadData());
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        // Clip behavior for the MAIN card corners
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header inside (with padding)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Text(
                    board.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'GeneralSans',
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BoardDetailPage(board: board),
                        ),
                      ).then((_) => _loadData());
                    },
                    child: const Icon(Icons.add, color: Colors.black, size: 24),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.black,
                    size: 24,
                  ),
                ],
              ),
            ),

            // Images List
            SizedBox(
              height: 140,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                scrollDirection: Axis.horizontal,
                itemCount: previewImages.isEmpty ? 1 : previewImages.length,
                // FIXED: Changed VerticalDivider to a Container to ensure it renders visible
                separatorBuilder:
                    (_, __) => Container(
                      width: 1,
                      color: const Color.fromARGB(
                        255,
                        169,
                        169,
                        169,
                      ), // Visible grey divider
                    ),
                itemBuilder: (context, index) {
                  if (previewImages.isEmpty) {
                    return Container(
                      width: 100,
                      color: Colors.grey[50],
                      child: const Center(
                        child: Text(
                          "Empty",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    );
                  }

                  final imagePath = previewImages[index];
                  return SizedBox(
                    width: 110,
                    // ADDED: ClipRRect for "very small image radius"
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0), // Small radius
                      child: Image.file(
                        File(imagePath),
                        fit: BoxFit.cover,
                        errorBuilder:
                            (c, e, s) => Container(
                              color: Colors.grey[100],
                              child: const Icon(
                                Icons.broken_image,
                                color: Colors.grey,
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
      ),
    );
  }
}
