import 'package:flutter/material.dart';

/// Displays a bottom-docked green SnackBar with centered white text and straight corners
/// that slides up smoothly from the bottom and slides back down towards the bottom when dismissed.
void showAppSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFF2E7D32),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      behavior: SnackBarBehavior.fixed,
      duration: const Duration(seconds: 2),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
      ),
    ),
  );
}
