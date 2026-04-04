import 'package:flutter/material.dart';

class RetroKeyboard extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onKeyTapped;

  const RetroKeyboard({
    super.key,
    required this.controller,
    this.onKeyTapped,
  });

  @override
  Widget build(BuildContext context) {
    final List<String> keys = [
      '1', '2', '3', '4', '5', '6', '7', '8', '9', '0',
      'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
      'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T',
      'U', 'V', 'W', 'X', 'Y', 'Z', 'BACKSPACE'
    ];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFC0C0C0),
        border: Border.all(color: Colors.black, width: 1),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: keys.map((key) {
          if (key == 'BACKSPACE') {
            return _RetroKey(
              onTap: _handleBackspace,
              child: const Icon(Icons.backspace_outlined, size: 20),
              width: 100,
            );
          }
          return _RetroKey(
            label: key,
            onTap: () => _handleKeyTap(key),
          );
        }).toList(),
      ),
    );
  }

  void _handleKeyTap(String key) {
    controller.text = controller.text + key;
    onKeyTapped?.call();
  }

  void _handleBackspace() {
    if (controller.text.isNotEmpty) {
      controller.text = controller.text.substring(0, controller.text.length - 1);
      onKeyTapped?.call();
    }
  }
}

class _RetroKey extends StatefulWidget {
  final String? label;
  final Widget? child;
  final VoidCallback onTap;
  final double width;

  const _RetroKey({
    this.label,
    this.child,
    required this.onTap,
    this.width = 45,
  });

  @override
  State<_RetroKey> createState() => _RetroKeyState();
}

class _RetroKeyState extends State<_RetroKey> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: Container(
        width: widget.width,
        height: 45, // Set a default fixed height
        decoration: BoxDecoration(
          color: const Color(0xFFC0C0C0),
          border: Border(
            top: BorderSide(
              color: _isPressed ? const Color(0xFF808080) : Colors.white,
              width: 3,
            ),
            left: BorderSide(
              color: _isPressed ? const Color(0xFF808080) : Colors.white,
              width: 3,
            ),
            right: BorderSide(
              color: _isPressed ? Colors.white : const Color(0xFF808080),
              width: 3,
            ),
            bottom: BorderSide(
              color: _isPressed ? Colors.white : const Color(0xFF808080),
              width: 3,
            ),
          ),
        ),
        child: Center(
          child: widget.child ??
              Text(
                widget.label!,
                style: const TextStyle(
                  fontFamily: 'Ambitsek',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
        ),
      ),
    );
  }
}
