import 'package:flutter/material.dart';
import 'package:creekui/ui/styles/variables.dart';

class NoteInputSheet extends StatefulWidget {
  final List<String> categories;
  final String initialCategory;
  final Function(String content, String category) onSubmit;

  const NoteInputSheet({
    super.key,
    required this.categories,
    required this.initialCategory,
    required this.onSubmit,
  });

  @override
  State<NoteInputSheet> createState() => _NoteInputSheetState();
}

class _NoteInputSheetState extends State<NoteInputSheet> {
  late String _selectedCategory;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFAFAFA),
                    width: 1.25,
                  ),
                ),
                child: const CircleAvatar(
                  radius: 15,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Alex", // TODO
                style: TextStyle(
                  fontFamily: 'GeneralSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E7FF),
                  borderRadius: BorderRadius.circular(1000),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value:
                        widget.categories.contains(_selectedCategory)
                            ? _selectedCategory
                            : null,
                    hint: const Text(
                      "Type",
                      style: TextStyle(fontFamily: 'GeneralSans', fontSize: 12),
                    ),
                    isDense: true,
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      size: 20,
                      color: Color(0xFF27272A),
                    ),
                    style: const TextStyle(
                      fontFamily: 'GeneralSans',
                      fontSize: 12,
                      color: Color(0xFF27272A),
                    ),
                    dropdownColor: Colors.white,
                    items:
                        widget.categories
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCategory = v);
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Input Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F4F5),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLines: null,
                    style: const TextStyle(
                      fontFamily: 'GeneralSans',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      hintText: "Enter note details...",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(
                  Icons.send,
                  color: Color(0xFF27272A),
                  size: 24,
                ),
                onPressed: () {
                  if (_controller.text.isNotEmpty) {
                    widget.onSubmit(_controller.text.trim(), _selectedCategory);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class NoteModalOverlay extends StatelessWidget {
  final Widget modalContent;
  final Size screenSize;

  const NoteModalOverlay({
    super.key,
    required this.modalContent,
    required this.screenSize,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenSize.height),
          child: Material(
            color: Colors.white,
            elevation: 10,
            shadowColor: Colors.black26,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: mq.padding.bottom),
              child: modalContent,
            ),
          ),
        ),
      ),
    );
  }
}
