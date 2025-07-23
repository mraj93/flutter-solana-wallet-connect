// wallets_utils.dart
// ignore_for_file: avoid_print

import 'package:flutter/material.dart';

Future<void> showHelperAlert(BuildContext ctx, String title) {
  return showDialog(
    context: ctx,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: const Text('This is a helper dialog from utils'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

void helloWallet() => print('✅ Hello from utility logic');

class WalletUtilityButtons extends StatelessWidget {
  const WalletUtilityButtons({super.key, required this.onConnect, required this.onSend});

  final Future<void> Function() onConnect;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () async {
            print('🔥 Connect');
            helloWallet();
            await showHelperAlert(context, 'Connecting…');
            await onConnect();
          },
          child: const Text('🔗 Connect Wallet'),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: () async {
            print('🔥 Send');
            helloWallet();
            await showHelperAlert(context, 'Sending…');
            await onSend();
          },
          child: const Text('📤 Send 0.001 SOL'),
        ),
      ],
    );
  }
}
