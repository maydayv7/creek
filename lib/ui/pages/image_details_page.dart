import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/models/image_model.dart';
import '../../data/models/comment_model.dart';
import '../../data/repos/image_repo.dart';
import '../../data/repos/comment_repo.dart';
import 'package:intl/intl.dart';

class ImageDetailPage extends StatefulWidget {
  final String imageId;

  const ImageDetailPage({super.key, required this.imageId});

  @override
  State<ImageDetailPage> createState() => _ImageDetailPageState();
}

class _ImageDetailPageState extends State<ImageDetailPage> {
  final _imageRepo = ImageRepository();
  final _commentRepo = CommentRepository();
  
  ImageModel? _image;
  List<Comment> _comments = [];
  bool _isLoading = true;
  
  // Input controllers
  final _commentController = TextEditingController();
  CommentType _selectedType = CommentType.layout; // Default type

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch detailed image info (including comments if repo supports it, 
      // or fetch separately if not fully integrated yet)
      final data = await _imageRepo.getImageDetails(widget.imageId);
      
      if (data != null) {
        // Parse Image
        _image = ImageModel.fromMap(data);
        
        // Parse Comments from the joined data
        if (data['comments'] != null) {
          final commentsList = data['comments'] as List;
          _comments = commentsList.map((c) => Comment.fromMap(c)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error loading details: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.trim().isEmpty || _image == null) return;

    final newComment = Comment(
      imageId: _image!.id,
      content: _commentController.text.trim(),
      type: _selectedType,
      createdAt: DateTime.now().toIso8601String(),
    );

    try {
      await _commentRepo.addComment(newComment);
      _commentController.clear();
      // Refresh data to show new comment
      await _loadData();
    } catch (e) {
      debugPrint("Error adding comment: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to add comment: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_image == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text("Image not found")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black),
            onPressed: () {
              // Share logic
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_horiz, color: Colors.black),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. IMAGE DISPLAY
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 500),
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.file(
                          File(_image!.filePath),
                          fit: BoxFit.contain,
                          errorBuilder: (c, e, s) => Container(
                            height: 300,
                            color: Colors.grey[200],
                            child: const Icon(Icons.broken_image, size: 50, color: Colors.grey),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. INFO (Name & Link)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _image!.name ?? "Untitled Image",
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'GeneralSans',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "https://www.adobe.com/project/...", // Placeholder or real link if you have it
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            decoration: TextDecoration.underline,
                            fontFamily: 'GeneralSans',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // 3. COMMENTS SECTION
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        const Text(
                          "Comments",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'GeneralSans',
                          ),
                        ),
                        const Spacer(),
                        // Analysis / Tag icons
                        const Icon(Icons.local_offer_outlined, size: 20, color: Colors.black),
                        const SizedBox(width: 12),
                        const Icon(Icons.fullscreen, size: 24, color: Colors.black),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (_comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Center(
                        child: Text(
                          "No comments yet. Add one below!",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: _comments.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        return _buildCommentItem(_comments[index]);
                      },
                    ),
                    
                  const SizedBox(height: 100), // Space for bottom sheet
                ],
              ),
            ),
          ),
        ],
      ),
      // 4. ADD COMMENT INPUT
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Type Selector (Dropdown or similar)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<CommentType>(
                        value: _selectedType,
                        icon: const Icon(Icons.arrow_drop_down),
                        items: CommentType.values.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(
                              type.name.toUpperCase(),
                              style: const TextStyle(fontSize: 12, fontFamily: 'GeneralSans'),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedType = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Text Input
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      decoration: const InputDecoration(
                        hintText: "Add a comment...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  // Send Button
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue),
                    onPressed: _addComment,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCommentItem(Comment comment) {
    final date = DateTime.tryParse(comment.createdAt);
    final timeStr = date != null ? DateFormat.jm().format(date) : "";

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Vertical Line indicator
        Container(
          width: 4,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Comment Type Tag (Pill)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      comment.type.name, // e.g. "Layout", "Colour"
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                        fontFamily: 'GeneralSans',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Time
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[400],
                      fontFamily: 'GeneralSans',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                comment.content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  height: 1.4,
                  fontFamily: 'GeneralSans',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}