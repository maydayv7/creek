import 'dart:io';
import 'package:flutter/material.dart';

import '../../data/repos/board_repo.dart';
import '../../data/repos/board_image_repo.dart';
import '../../data/models/board_model.dart';
import '../../data/models/image_model.dart';

class BoardListPage extends StatefulWidget {
  const BoardListPage({super.key});

  @override
  State<BoardListPage> createState() => _BoardListPageState();
}

class _BoardListPageState extends State<BoardListPage> {
  final boardRepo = BoardRepository();
  List<Board> boards = [];

  @override
  void initState() {
    super.initState();
    loadBoards();
  }

  Future<void> loadBoards() async {
    final result = await boardRepo.getBoards();
    boards = result.map((e) => Board.fromMap(e)).toList();
    if (mounted) setState(() {});
  }

  Future<void> createBoardDialog() async {
    final nameController = TextEditingController();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("Create New Board"),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(hintText: "Board name"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
            },
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await boardRepo.createBoard(nameController.text);
                if (!c.mounted) return;
                Navigator.pop(c);
                await loadBoards();
              }
            },
            child: Text("Create"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Boards"),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
            onPressed: createBoardDialog,
          )
        ],
      ),

      body: boards.isEmpty
          ? Center(child: Text("No boards yet"))
          : GridView.builder(
              padding: EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: boards.length,
              itemBuilder: (c, i) {
                final board = boards[i];

                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BoardDetailPage(board: board),
                      ),
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.grey.shade300,
                    ),
                    child: Center(
                      child: Text(
                        board.name,
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------
// BOARD DETAIL PAGE
// ---------------------------------------------------------

class BoardDetailPage extends StatefulWidget {
  final Board board;

  const BoardDetailPage({super.key, required this.board});

  @override
  State<BoardDetailPage> createState() => _BoardDetailPageState();
}

class _BoardDetailPageState extends State<BoardDetailPage> {
  final boardImageRepo = BoardImageRepository();
  List<ImageModel> images = [];

  @override
  void initState() {
    super.initState();
    loadImages();
  }

  Future<void> loadImages() async {
    final result = await boardImageRepo.getImagesOfBoard(widget.board.id);

    images = result
        .map((e) => ImageModel(
              id: e['id'],
              filePath: e['filePath'],
            ))
        .toList();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.board.name),
      ),
      body: images.isEmpty
          ? Center(child: Text("No images in this board yet"))
          : GridView.builder(
              padding: EdgeInsets.all(12),
              itemCount: images.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                final img = images[index];

                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(img.filePath),
                    fit: BoxFit.cover,
                  ),
                );
              },
            ),
    );
  }
}
