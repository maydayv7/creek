// lib/ui/pages/home_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:adobe/data/repos/board_repo.dart';
import 'package:adobe/data/repos/board_image_repo.dart';
import 'package:adobe/data/models/board_model.dart';
import 'package:adobe/ui/pages/board_detail_page.dart';
import 'package:adobe/ui/pages/image_analysis_page.dart';
import 'package:adobe/ui/pages/all_image_page.dart';
import 'package:adobe/services/board_services.dart';
import 'package:adobe/services/theme_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _boardRepo = BoardRepository();
  final _boardService = BoardService();
  late Future<List<Board>> _boardsFuture;

  @override
  void initState() {
    super.initState();
    _refreshBoards();
  }

  void _refreshBoards() {
    setState(() {
      _boardsFuture = _boardRepo.getBoards().then((data) {
        return data.map((e) => Board.fromMap(e)).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("My Boards", style: TextStyle(fontWeight: FontWeight.bold)),
            Text("Long press a board for options", style: TextStyle(fontSize: 12)),
          ],
        ),
        centerTitle: true,
        leading: IconButton(
          // THEME TOGGLE BUTTON
          icon: Icon(themeService.mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () {
            themeService.toggleTheme();
          },
          tooltip: 'Toggle Theme',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImageAnalysisPage()),
              );
            },
            tooltip: 'Image Analysis',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateBoardDialog,
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshBoards(),
        child: FutureBuilder<List<Board>>(
          future: _boardsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final boards = snapshot.data ?? [];

            return GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: boards.length + 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85, // Taller cards to fit images + text
              ),
              itemBuilder: (context, index) {
                if (index == 0) return _buildAllImagesCard();
                final board = boards[index - 1];
                return BoardCard(
                  board: board,
                  onTap: () {
                     Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BoardDetailPage(board: board)),
                    ).then((_) => _refreshBoards());
                  },
                  onLongPress: () => _showBoardOptions(board),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildAllImagesCard() {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AllImagesPage()),
        ).then((_) => _refreshBoards());
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.purple.shade200, Colors.blue.shade200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 4)),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.collections, size: 48, color: Colors.white),
            SizedBox(height: 8),
            Text(
              "All Images",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            Text(
              "Master Collection",
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  // --- MENU LOGIC ---
  void _showBoardOptions(Board board) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(board.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text("Rename Board"),
              onTap: () { Navigator.pop(context); _showRenameDialog(board); },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline, color: Colors.orange),
              title: const Text("Move/Copy All Images"),
              onTap: () { Navigator.pop(context); _showBulkTransferDialog(board); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text("Delete Board"),
              onTap: () { Navigator.pop(context); _showDeleteBoardDialog(board); },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(Board board) {
    final controller = TextEditingController(text: board.name);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Rename Board"),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              await _boardService.renameBoard(board.id, controller.text);
              if (c.mounted) Navigator.pop(c);
              _refreshBoards();
            },
            child: const Text("Rename"),
          ),
        ],
      ),
    );
  }

  void _showDeleteBoardDialog(Board board) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("Delete '${board.name}'?"),
        content: const Text("Choose delete mode:"),
        actions: [
          TextButton(
            onPressed: () async {
              await _boardService.deleteBoardOnly(board.id);
              if (c.mounted) Navigator.pop(c);
              _refreshBoards();
            },
            child: const Text("Just Board"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await _boardService.deleteBoardAndContent(board.id);
              if (c.mounted) Navigator.pop(c);
              _refreshBoards();
            },
            child: const Text("Delete All"),
          ),
        ],
      ),
    );
  }

  void _showBulkTransferDialog(Board sourceBoard) async {
    final boards = await _boardRepo.getBoards();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Transfer Images"),
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: ListView.builder(
            itemCount: boards.length,
            itemBuilder: (context, index) {
              final target = Board.fromMap(boards[index]);
              if (target.id == sourceBoard.id) return const SizedBox.shrink();
              return ListTile(
                title: Text(target.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      child: const Text("Copy"),
                      onPressed: () async {
                        await _boardService.copyAllImages(sourceBoard.id, target.id);
                        if (c.mounted) { Navigator.pop(c); _refreshBoards(); }
                      },
                    ),
                    TextButton(
                      child: const Text("Move"),
                      onPressed: () async {
                        await _boardService.moveAllImages(sourceBoard.id, target.id);
                        if (c.mounted) { Navigator.pop(c); _refreshBoards(); }
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showCreateBoardDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("New Board"),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: "Name"), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await _boardRepo.createBoard(controller.text);
                if (c.mounted) Navigator.pop(c);
                _refreshBoards();
              }
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// NEW: SMART BOARD CARD WIDGET WITH COLLAGE PREVIEW
// =========================================================

class BoardCard extends StatefulWidget {
  final Board board;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const BoardCard({super.key, required this.board, required this.onTap, required this.onLongPress});

  @override
  State<BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<BoardCard> {
  final _imgRepo = BoardImageRepository();
  late Future<List<String>> _previewImages;

  @override
  void initState() {
    super.initState();
    // Fetch the 4 preview images for this specific card
    _previewImages = _imgRepo.getBoardPreviewImages(widget.board.id);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. The Image/Collage Area
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FutureBuilder<List<String>>(
                  future: _previewImages,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      // EMPTY STATE
                      return Center(
                        child: Icon(Icons.dashboard_customize_outlined, size: 40, color: Colors.grey[400]),
                      );
                    }
                    
                    final images = snapshot.data!;
                    return _buildCollage(images);
                  },
                ),
              ),
            ),
          ),
          
          // 2. The Title Area
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
            child: Column(
              children: [
                Text(
                  widget.board.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollage(List<String> paths) {
    // Helper to build a single image tile with memory caching optimization
    Widget img(String path) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 300, // Optimize memory for thumbnails
        errorBuilder: (_, __, ___) => Container(color: Colors.grey[300], child: const Icon(Icons.broken_image, size: 16, color: Colors.grey)),
      );
    }

    if (paths.length == 1) {
      return img(paths[0]);
    } else if (paths.length == 2) {
      return Row(
        children: [
          Expanded(child: img(paths[0])),
          const SizedBox(width: 1),
          Expanded(child: img(paths[1])),
        ],
      );
    } else if (paths.length == 3) {
      return Row(
        children: [
          Expanded(child: img(paths[0])),
          const SizedBox(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: img(paths[1])),
                const SizedBox(height: 1),
                Expanded(child: img(paths[2])),
              ],
            ),
          ),
        ],
      );
    } else {
      // 4 or more
      return Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(child: img(paths[0])),
                const SizedBox(width: 1),
                Expanded(child: img(paths[1])),
              ],
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(child: img(paths[2])),
                const SizedBox(width: 1),
                Expanded(child: img(paths[3])),
              ],
            ),
          ),
        ],
      );
    }
  }
}