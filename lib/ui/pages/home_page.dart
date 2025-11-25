// lib/ui/pages/home_page.dart

import 'package:flutter/material.dart';
import 'package:adobe/data/repos/board_repo.dart';
import 'package:adobe/data/models/board_model.dart';
import 'package:adobe/ui/pages/board_detail_page.dart';
import 'package:adobe/ui/pages/image_analysis_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _boardRepo = BoardRepository();
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
        title: const Text("My Boards"),
        centerTitle: true,
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
      // Pull to Refresh allows you to update the list after sharing an image
      body: RefreshIndicator(
        onRefresh: () async => _refreshBoards(),
        child: FutureBuilder<List<Board>>(
          future: _boardsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 200),
                  Center(child: Text("No boards yet. Create one!")),
                ],
              );
            }

            final boards = snapshot.data!;

            return GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: boards.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.2, // Rectangular cards
              ),
              itemBuilder: (context, index) {
                final board = boards[index];
                return _buildBoardCard(board);
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildBoardCard(Board board) {
    return GestureDetector(
      onTap: () {
        // Navigate to the details of this board
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => BoardDetailPage(board: board)),
        ).then((_) => _refreshBoards()); // Refresh when coming back
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.dashboard, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              board.name,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              "Tap to view",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateBoardDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder:
          (c) => AlertDialog(
            title: const Text("New Board"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: "Board Name"),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text("Cancel"),
              ),
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
