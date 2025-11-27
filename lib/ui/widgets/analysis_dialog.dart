import 'dart:convert';
import 'package:flutter/material.dart';
import '../../data/models/image_model.dart';

class AnalysisDialog extends StatelessWidget {
  final ImageModel image;

  const AnalysisDialog({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    if (image.analysisData == null) {
      return const AlertDialog(content: Text("No analysis data available."));
    }

    Map<String, dynamic> data;
    try {
      data = json.decode(image.analysisData!);
    } catch (e) {
      return const AlertDialog(content: Text("Corrupt analysis data."));
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Image Intelligence", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  // 1. Layout
                  if (data['layout'] != null && data['layout']['top5'] != null)
                    _buildSection(
                      "Composition",
                      Icons.grid_goldenratio,
                      Colors.blue,
                      _buildList(data['layout']['top5']),
                    ),

                  // 2. Texture
                  if (data['texture'] != null && (data['texture'] as List).isNotEmpty)
                    _buildSection(
                      "Texture",
                      Icons.texture,
                      Colors.orange,
                      Wrap(
                        spacing: 8,
                        children: (data['texture'] as List).map((t) => Chip(
                          label: Text("${t['name']} ${(t['score']*100).toInt()}%"),
                          backgroundColor: Colors.orange.shade50,
                          avatar: const CircleAvatar(radius: 8, backgroundColor: Colors.orange),
                        )).toList(),
                      ),
                    ),

                  // 3. Color
                  if (data['color'] != null)
                    _buildSection(
                      "Color Style",
                      Icons.palette,
                      Colors.purple,
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (data['color']['top_label'] ?? 'Unknown').toString().toUpperCase(),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.purple),
                          ),
                          LinearProgressIndicator(
                            value: (data['color']['top_score'] as num?)?.toDouble() ?? 0.0,
                            color: Colors.purple,
                            backgroundColor: Colors.purple.shade50,
                          ),
                        ],
                      ),
                    ),

                  // 4. Embeddings
                  if (data['embedding'] != null)
                    _buildSection(
                      "AI Style",
                      Icons.auto_awesome,
                      Colors.indigo,
                      Wrap(
                        spacing: 6,
                        children: (data['embedding']['top5'] as List? ?? []).map<Widget>((e) => Chip(
                          label: Text(e['name'], style: const TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                        )).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, IconData icon, Color color, Widget content) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12), 
        side: BorderSide(color: color.withOpacity(0.2))
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ]),
            const SizedBox(height: 12),
            content,
          ],
        ),
      ),
    );
  }

  Widget _buildList(List items) {
    return Column(
      children: items.map((item) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(item['name'], style: const TextStyle(fontWeight: FontWeight.w500)),
            Text("${(item['score'] * 100).toStringAsFixed(1)}%", style: const TextStyle(color: Colors.grey)),
          ],
        ),
      )).toList(),
    );
  }
}
