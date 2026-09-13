import 'package:flutter/material.dart';
import 'orion_typography.dart';

/// The export's solid cyan action, shared by full-screen scene actions.
class OrionPrimaryButton extends StatelessWidget {
  const OrionPrimaryButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: onPressed == null
          ? null
          : const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF7FF0FF), Color(0xFF13B8E6), Color(0xFF0A7EA3)],
              stops: [0, .6, 1],
            ),
      color: onPressed == null ? const Color(0xFF23384A) : null,
    ),
    child: TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(60),
        foregroundColor: const Color(0xFF04222C),
        disabledForegroundColor: const Color(0xFF8EA4B5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      icon: Icon(icon, size: 24),
      label: Text(
        label,
        style: OrionTypography.microLabel(
          size: 13,
          color: onPressed == null
              ? const Color(0xFF8EA4B5)
              : const Color(0xFF04222C),
        ),
      ),
    ),
  );
}
