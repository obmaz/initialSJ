import 'package:flutter/material.dart';

class RetroButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? color;

  const RetroButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 60,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? Colors.red.shade900,
          foregroundColor: Colors.white,
          elevation: 0,
          side: const BorderSide(color: Colors.white, width: 2),
          shape: const BeveledRectangleBorder(),
          // User preference: No hover or focus effects
          splashFactory: NoSplash.splashFactory,
          shadowColor: Colors.transparent,
        ).copyWith(overlayColor: WidgetStateProperty.all(Colors.transparent)),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
