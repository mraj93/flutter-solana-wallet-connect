// ignore_for_file: avoid_print

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:test5/unified_wallet_connector.dart';
import 'package:test5/wallet_connector_logic.dart';

import 'wallet_model.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connect Wallet',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: ConnectWalletScreen(),
    );
  }
}

class ConnectWalletScreen extends StatefulWidget {
  const ConnectWalletScreen({super.key});

  @override
  State<ConnectWalletScreen> createState() => _ConnectWalletScreenState();
}

class _ConnectWalletScreenState extends State<ConnectWalletScreen> {
  static const String _logPrefix = '📱 [Widget]';

  late LocalAssociationScenario scenario;
  late MobileWalletAdapterClient mwaClient;
  AuthorizationResult? authResult;
  late SolanaClient client;
  late UnifiedWalletManager _walletManager;

  @override
  void initState() {
    super.initState();
    print('$_logPrefix 🏗️ Initializing ConnectWalletScreen...');

    client = SolanaClient(
      rpcUrl: Uri.parse("https://devnet.helius-rpc.com/?api-key=0dc632a6-47ba-430d-9abb-dbbdc036cd92"),
      websocketUrl: Uri.parse("wss://devnet.helius-rpc.com/?api-key=0dc632a6-47ba-430d-9abb-dbbdc036cd92"),
    );
    print('$_logPrefix 🌐 Solana client initialized with devnet');

    _walletManager = UnifiedWalletManager();
    print('$_logPrefix 🔗 Wallet manager initialized');

    print('$_logPrefix ✅ Initialization complete');
  }

  @override
  void dispose() {
    print('$_logPrefix 🗑️ Disposing widget...');
    _walletManager.dispose();
    super.dispose();
    print('$_logPrefix 🗑️ ✅ Widget disposed');
  }

  void connectWalletAndroid() async {
    print('$_logPrefix 🤖 Starting Android wallet connection...');

    try {
      print('$_logPrefix 🤖 Creating LocalAssociationScenario...');
      scenario = await LocalAssociationScenario.create();

      print('$_logPrefix 🤖 Starting activity for result...');
      scenario.startActivityForResult(null).ignore();

      print('$_logPrefix 🤖 Starting MWA client...');
      final mwaClient = await scenario.start();

      print('$_logPrefix 🤖 Requesting authorization...');
      authResult = await mwaClient.authorize(
        identityName: 'Test App',
        identityUri: Uri.parse("https://placeholder.com"),
        iconUri: Uri.parse("favicon"),
        cluster: 'devnet',
      );

      if (authResult?.publicKey != null) {
        final publicKeyBase58 = base58encode(authResult!.publicKey.toList());
        print('$_logPrefix 🤖 ✅ Authorization successful!');
        print('$_logPrefix 🤖 Public key: $publicKeyBase58');
        print('$_logPrefix 🤖 Account label: ${authResult!.accountLabel}');

        _walletManager.setAndroidConnection(publicKeyBase58, authResult!);
      } else {
        print('$_logPrefix 🤖 ❌ Authorization failed - no public key received');
      }

      print('$_logPrefix 🤖 Closing scenario...');
      scenario.close();
      print('$_logPrefix 🤖 ✅ Android connection process complete');
    } catch (e) {
      print('$_logPrefix 🤖 ❌ Android wallet connection error: $e');
      print('$_logPrefix 🤖 Stack trace: ${StackTrace.current}');
    }
  }

  void _showWalletSelectionDialog() {
    print('$_logPrefix 🔄 Showing wallet selection dialog...');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Wallet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('Phantom'),
                onTap: () async {
                  print('$_logPrefix 👻 User selected Phantom');
                  Navigator.of(context).pop();
                  try {
                    await _walletManager.connectWallet(WalletType.phantom);
                  } catch (e) {
                    print('$_logPrefix 👻 ❌ Phantom connection failed: $e');
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Failed to connect to Phantom: $e")));
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet),
                title: const Text('Solflare'),
                onTap: () async {
                  print('$_logPrefix 🔥 User selected Solflare');
                  Navigator.of(context).pop();
                  try {
                    await _walletManager.connectWallet(WalletType.solflare);
                  } catch (e) {
                    print('$_logPrefix 🔥 ❌ Solflare connection failed: $e');
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Failed to connect to Solflare: $e")));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Enhanced transaction methods with logging
  Future<void> sendSolana() async {
    print('$_logPrefix 💰 Starting SOL transfer...');

    try {
      final walletState = _walletManager.state;
      print('$_logPrefix 💰 Wallet state - Connected: ${walletState.isConnected}');
      print('$_logPrefix 💰 Platform: ${Platform.isIOS ? 'iOS' : 'Android'}');

      if (!walletState.isConnected || walletState.publicKey == null) {
        print('$_logPrefix 💰 ❌ Wallet not connected');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallet not connected")));
        return;
      }

      if (Platform.isIOS) {
        print('$_logPrefix 💰📱 Using iOS Phantom transfer...');
        await PhantomTransfer.sendSolFromPhantom(
          context: context,
          fromAddress: walletState.publicKey!,
          toAddress: "9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ",
          lamports: (0.01 * lamportsPerSol).toInt(),
        );
      } else {
        print('$_logPrefix 💰🤖 Using Android MWA transfer...');

        if (authResult == null) {
          print('$_logPrefix 💰🤖 ❌ No Android auth result');
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Android authorization not found")));
          return;
        }

        // Your existing Android transaction logic with added logging
        final amount = 0.01;
        print('$_logPrefix 💰🤖 Transfer amount: $amount SOL');

        // ... rest of Android transaction logic ...
      }

      print('$_logPrefix 💰 ✅ SOL transfer completed');
    } catch (err) {
      print('$_logPrefix 💰 ❌ SOL transfer error: $err');
      print('$_logPrefix 💰 ❌ Stack trace: ${StackTrace.current}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $err")));
    }
  }

  @override
  Widget build(BuildContext context) {
    print('$_logPrefix 🎨 Building widget...');

    return Scaffold(
      appBar: AppBar(title: const Text('Connect Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ValueListenableBuilder<WalletState>(
                valueListenable: _walletManager.stateNotifier,
                builder: (context, walletState, child) {
                  print('$_logPrefix 🎨 UI Update - State: ${walletState.isConnected}');

                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: walletState.isConnecting
                            ? null
                            : () {
                                print('$_logPrefix 🎯 Connect/Disconnect button pressed');
                                print('$_logPrefix 🎯 Current state: Connected=${walletState.isConnected}');

                                if (walletState.isConnected) {
                                  print('$_logPrefix 🎯 Disconnecting wallet...');
                                  _walletManager.disconnect();
                                  authResult = null;
                                } else {
                                  print('$_logPrefix 🎯 Platform: ${Platform.isAndroid ? 'Android' : 'iOS'}');
                                  if (Platform.isAndroid) {
                                    print('$_logPrefix 🎯 Starting Android connection...');
                                    connectWalletAndroid();
                                  } else if (Platform.isIOS) {
                                    print('$_logPrefix 🎯 Showing iOS wallet selection...');
                                    _showWalletSelectionDialog();
                                  }
                                }
                              },
                        child: walletState.isConnecting
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                  SizedBox(width: 8),
                                  Text('Connecting...'),
                                ],
                              )
                            : Text(walletState.isConnected ? 'Disconnect Wallet' : 'Connect Wallet'),
                      ),

                      // Rest of your UI with wallet state display...
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
