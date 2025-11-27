// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:adobe/data/repos/board_repo.dart';
// import 'package:adobe/data/repos/board_image_repo.dart';

// class MoodboardsPage extends StatefulWidget {
//   const MoodboardsPage({super.key});

//   @override
//   State<MoodboardsPage> createState() => _MoodboardsPageState();
// }

// class _MoodboardsPageState extends State<MoodboardsPage> {
//   final _boardRepo = BoardRepository();
//   final _boardImageRepo = BoardImageRepository();
//   final _searchController = TextEditingController();

//   List<Map<String, dynamic>> _allBoards = [];
//   List<Map<String, dynamic>> _filteredBoards = [];
//   bool _isLoading = true;

//   @override
//   void initState() {
//     super.initState();
//     _loadData();
//     _searchController.addListener(_onSearchChanged);
//   }

//   Future<void> _loadData() async {
//     // 1. Fetch Boards
//     final boards = await _boardRepo.getBoards();

//     // 2. (Optional) Fetch a thumbnail image for each board to make it look good
//     // This is a simulated join. In a real app, do this in the SQL query.
//     List<Map<String, dynamic>> enrichedBoards = [];

//     for (var board in boards) {
//       // Get the first image of this board to serve as cover
//       final images = await _boardImageRepo.getImagesForBoard(board['id']);
//       String? coverPath;
//       if (images.isNotEmpty) {
//         coverPath = images.first['filePath'];
//       }

//       enrichedBoards.add({
//         ...board,
//         'coverPath': coverPath,
//         // If your DB doesn't have a 'project' column yet, we mock it for the UI demo
//         // You should add 'project' TEXT to your board_repo.dart create table
//         'project': board['project'] ?? 'General Projects',
//       });
//     }

//     if (mounted) {
//       setState(() {
//         _allBoards = enrichedBoards;
//         _filteredBoards = enrichedBoards;
//         _isLoading = false;
//       });
//     }
//   }

//   void _onSearchChanged() {
//     final query = _searchController.text.toLowerCase();
//     setState(() {
//       _filteredBoards =
//           _allBoards.where((board) {
//             final name = (board['name'] as String).toLowerCase();
//             final project = (board['project'] as String).toLowerCase();
//             return name.contains(query) || project.contains(query);
//           }).toList();
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white, // Match screenshot background
//       appBar: AppBar(
//         backgroundColor: Colors.white,
//         elevation: 0,
//         leading: IconButton(
//           icon: const Icon(
//             Icons.arrow_back_ios_new,
//             size: 20,
//             color: Colors.black,
//           ),
//           onPressed: () => Navigator.pop(context),
//         ),
//         title: const Text(
//           "MoodBoards",
//           style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
//         ),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.add, color: Colors.black),
//             onPressed: () {
//               // Add new board logic
//             },
//           ),
//         ],
//       ),
//       body:
//           _isLoading
//               ? const Center(child: CircularProgressIndicator())
//               : Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 20),
//                 child: ListView(
//                   physics: const BouncingScrollPhysics(),
//                   children: [
//                     const SizedBox(height: 10),

//                     // --- 1. SEARCH BAR ---
//                     Container(
//                       decoration: BoxDecoration(
//                         color: Colors.grey[200], // Match Screenshot grey
//                         borderRadius: BorderRadius.circular(12),
//                       ),
//                       child: TextField(
//                         controller: _searchController,
//                         decoration: const InputDecoration(
//                           hintText: "Search",
//                           prefixIcon: Icon(Icons.search, color: Colors.grey),
//                           border: InputBorder.none,
//                           contentPadding: EdgeInsets.symmetric(vertical: 14),
//                         ),
//                       ),
//                     ),

//                     const SizedBox(height: 24),

//                     // --- 2. RECENT PROJECTS ---
//                     const Text(
//                       "Recent Projects/Events",
//                       style: TextStyle(
//                         fontSize: 14,
//                         color: Colors.black54,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                     const SizedBox(height: 12),

//                     // Take top 3 items for "Recent"
//                     ..._filteredBoards
//                         .take(3)
//                         .map((board) => _buildRecentCard(board)),

//                     const SizedBox(height: 24),

//                     // --- 3. ALL PROJECTS (Accordion Style) ---
//                     const Text(
//                       "All Projects/Events",
//                       style: TextStyle(
//                         fontSize: 14,
//                         color: Colors.black54,
//                         fontWeight: FontWeight.w500,
//                       ),
//                     ),
//                     const SizedBox(height: 12),

//                     _buildAllProjectsList(),

//                     const SizedBox(height: 40),
//                   ],
//                 ),
//               ),
//     );
//   }

//   // --- WIDGET: The Card for Recent Items ---
//   Widget _buildRecentCard(Map<String, dynamic> board) {
//     return Container(
//       margin: const EdgeInsets.only(bottom: 12),
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(16),
//         border: Border.all(color: Colors.grey.shade200),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.03),
//             blurRadius: 10,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: ListTile(
//         contentPadding: const EdgeInsets.all(8),
//         leading: Container(
//           width: 60,
//           height: 60,
//           decoration: BoxDecoration(
//             borderRadius: BorderRadius.circular(12),
//             color: Colors.grey[100],
//             image:
//                 board['coverPath'] != null
//                     ? DecorationImage(
//                       image: FileImage(File(board['coverPath'])),
//                       fit: BoxFit.cover,
//                     )
//                     : null,
//           ),
//           child:
//               board['coverPath'] == null
//                   ? Icon(Icons.dashboard, color: Colors.grey[400])
//                   : null,
//         ),
//         title: Text(
//           board['project'].toString(),
//           style: TextStyle(fontSize: 12, color: Colors.grey[600]),
//         ),
//         subtitle: Text(
//           board['name'],
//           style: const TextStyle(
//             fontSize: 16,
//             fontWeight: FontWeight.bold,
//             color: Colors.black,
//           ),
//         ),
//         onTap: () {
//           // Navigate to Board Details
//         },
//       ),
//     );
//   }

//   // --- WIDGET: The Accordion List for "All Projects" ---
//   Widget _buildAllProjectsList() {
//     // 1. Group boards by 'Project'
//     // { "Bakery": [board1, board2], "Run Club": [board3] }
//     Map<String, List<Map<String, dynamic>>> grouped = {};

//     for (var board in _filteredBoards) {
//       String project = board['project'] ?? "Uncategorized";
//       if (!grouped.containsKey(project)) {
//         grouped[project] = [];
//       }
//       grouped[project]!.add(board);
//     }

//     // 2. Build Expansion Tiles
//     return Column(
//       children:
//           grouped.entries.map((entry) {
//             String projectName = entry.key;
//             List<Map<String, dynamic>> projectBoards = entry.value;

//             // Generate a random-ish color for the avatar based on name length
//             Color avatarColor =
//                 Colors
//                     .primaries[projectName.length % Colors.primaries.length]
//                     .shade100;
//             Color textColor =
//                 Colors
//                     .primaries[projectName.length % Colors.primaries.length]
//                     .shade700;

//             return Container(
//               margin: const EdgeInsets.only(bottom: 10),
//               decoration: BoxDecoration(
//                 color:
//                     Colors.grey[50], // Very light grey background for the group
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(color: Colors.grey.shade200),
//               ),
//               child: ExpansionTile(
//                 shape: const Border(), // Remove default divider borders
//                 collapsedShape: const Border(),
//                 leading: Container(
//                   width: 48,
//                   height: 48,
//                   decoration: BoxDecoration(
//                     color: avatarColor,
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Center(
//                     child: Text(
//                       projectName.substring(0, 1).toUpperCase(), // First letter
//                       style: TextStyle(
//                         fontSize: 20,
//                         fontWeight: FontWeight.bold,
//                         color: textColor,
//                       ),
//                     ),
//                   ),
//                 ),
//                 title: Text(
//                   projectName,
//                   style: const TextStyle(
//                     fontWeight: FontWeight.bold,
//                     fontSize: 16,
//                   ),
//                 ),
//                 children:
//                     projectBoards.map((board) {
//                       return Container(
//                         decoration: const BoxDecoration(
//                           border: Border(top: BorderSide(color: Colors.white)),
//                         ),
//                         child: ListTile(
//                           contentPadding: const EdgeInsets.only(
//                             left: 70,
//                             right: 20,
//                             bottom: 8,
//                           ),
//                           title: Text(
//                             board['name'],
//                             style: const TextStyle(fontWeight: FontWeight.w500),
//                           ),
//                           trailing: const Icon(
//                             Icons.arrow_forward_ios,
//                             size: 14,
//                             color: Colors.grey,
//                           ),
//                           onTap: () {
//                             // Navigate to Board Details
//                           },
//                         ),
//                       );
//                     }).toList(),
//               ),
//             );
//           }).toList(),
//     );
//   }
// }
