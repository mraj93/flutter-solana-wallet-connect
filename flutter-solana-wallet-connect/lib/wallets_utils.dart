// wallets_utils.dart

// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

// 🔧 Custom logic function inside utility file
Future<void> showHelperAlert(BuildContext context, String title) async {
  await showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text("This is a helper dialog from utils"),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))],
    ),
  );
}

void helloWallet() {
  print("✅ Hello from utility logic");
}

class WalletUtilityButtons extends StatelessWidget {
  final Future<void> Function() onFirstPressed;
  final Future<void> Function() onSecondPressed;

  const WalletUtilityButtons({super.key, required this.onFirstPressed, required this.onSecondPressed});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            print("🔥 Connect Button Pressed");
            helloWallet(); // ✅ Extra logic
            await showHelperAlert(context, "Connecting..."); // ✅ Show dialog
            await onFirstPressed(); // ✅ Call original function
          },
          child: Text("🔗 Connect Wallet"),
        ),
        SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            print("🔥 Send Button Pressed");
            helloWallet();
            await showHelperAlert(context, "Sending...");
            await onSecondPressed();
          },
          child: Text("📤 Send 0.001 SOL"),
        ),
      ],
    );
  }
}
