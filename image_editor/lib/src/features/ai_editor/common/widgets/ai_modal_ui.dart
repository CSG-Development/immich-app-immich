import 'package:flutter/material.dart';

class AiModalUi {
  const AiModalUi._();

  static const double sectionSpacing = 16;
  static const double itemSpacing = 8;
  static const double radius = 12;

  static const TextStyle sectionTitleStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const TextStyle contentStyle = TextStyle(fontSize: 13);
  static const TextStyle noteStyle = TextStyle(fontSize: 12);
  static const TextStyle selectorLabelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    color: Colors.black87,
  );
  static const TextStyle selectorValueStyle = TextStyle(fontSize: 11, color: Colors.black87);

  static InputDecoration selectDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      labelStyle: selectorValueStyle,
      floatingLabelStyle: selectorValueStyle,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.white30),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.white24),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: Colors.white54),
      ),
    );
  }

  static BoxDecoration selectorDecoration({required bool isActive}) {
    return BoxDecoration(
      color: isActive ? Colors.black54 : Colors.black87,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: isActive ? Colors.white54 : Colors.white24),
    );
  }
}

class AiModalSelectTile extends StatelessWidget {
  const AiModalSelectTile({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? Colors.white : Colors.white70;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AiModalUi.radius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: AiModalUi.selectorDecoration(isActive: isSelected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 6),
              Text(label, style: AiModalUi.selectorLabelStyle.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}

