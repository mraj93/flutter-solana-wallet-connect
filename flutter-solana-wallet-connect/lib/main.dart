// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:solana/base58.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'unified_wallet_connector.dart';
import 'wallet_model.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solana Wallet',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)),
      home: const ConnectWalletScreen(),
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

  // Android MWA variables
  late LocalAssociationScenario scenario;
  late MobileWalletAdapterClient mwaClient;
  AuthorizationResult? authResult; // For Android MWA

  // Solana client and unified manager
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

    _walletManager = UnifiedWalletManager(solanaClient: client);
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

  // ========== ANDROID MWA CONNECTION ==========
  Future<void> connectWalletAndroid() async {
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

        // Update the unified wallet manager with Android connection
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

  // ========== iOS WALLET SELECTION ==========
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
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("Failed to connect to Phantom: $e")));
                    }
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
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text("Failed to connect to Solflare: $e")));
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ========== ANDROID MWA REAUTHORIZATION ==========
  Future<bool> _doReauthorize(MobileWalletAdapterClient mwaClient) async {
    try {
      final reauthorized = await mwaClient.reauthorize(
        identityUri: Uri.parse("https://placeholder.com"),
        iconUri: Uri.parse("favicon.ico"),
        identityName: "Workshop",
        authToken: authResult!.authToken,
      );
      return reauthorized?.publicKey != null;
    } catch (err) {
      print('$_logPrefix 🤖 ❌ Reauthorization failed: $err');
      return false;
    }
  }

  // ========== TRANSACTION METHODS ==========
  Future<void> sendSolana() async {
    print('$_logPrefix 💰 Starting SOL transfer...');

    try {
      final walletState = _walletManager.stateNotifier.value;
      print('$_logPrefix 💰 Wallet state - Connected: ${walletState.isConnected}');
      print('$_logPrefix 💰 Platform: ${Platform.isIOS ? 'iOS' : 'Android'}');

      if (!walletState.isConnected || walletState.publicKey == null) {
        print('$_logPrefix 💰 ❌ Wallet not connected');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallet not connected")));
        }
        return;
      }

      if (Platform.isIOS) {
        print('$_logPrefix 💰📱 Using iOS deep linking transfer...');
        await _sendIOSTransaction();
      } else {
        print('$_logPrefix 💰🤖 Using Android MWA transfer...');
        await _sendAndroidTransaction();
      }

      print('$_logPrefix 💰 ✅ SOL transfer completed');
    } catch (err) {
      print('$_logPrefix 💰 ❌ SOL transfer error: $err');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $err")));
      }
    }
  }

  // iOS Transaction via Deep Links
  Future<void> _sendIOSTransaction() async {
    // For iOS, we would need to implement deep link transaction sending
    // This is a placeholder for iOS transaction logic
    print('$_logPrefix 💰📱 iOS transaction implementation needed');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("iOS transactions not yet implemented")));
    }
  }

  // Android Transaction via MWA
  Future<void> _sendAndroidTransaction() async {
    if (authResult == null) {
      print('$_logPrefix 💰🤖 ❌ No Android auth result');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Android authorization not found")));
      }
      return;
    }

    final amount = 0.01;
    final receiver = Ed25519HDPublicKey.fromBase58("9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ");

    print('$_logPrefix 💰🤖 Transfer amount: $amount SOL');
    print('$_logPrefix 💰🤖 Receiver: ${receiver.toBase58()}');

    scenario = await LocalAssociationScenario.create();
    scenario.startActivityForResult(null).ignore();
    final mwaClient = await scenario.start();

    if (!await _doReauthorize(mwaClient)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Reauthorization failed")));
      }
      await scenario.close();
      return;
    }

    final signer = Ed25519HDPublicKey(authResult!.publicKey);
    final blockhash = (await client.rpcClient.getLatestBlockhash()).value.blockhash;
    final instruction = SystemInstruction.transfer(
      fundingAccount: signer,
      recipientAccount: receiver,
      lamports: (amount * lamportsPerSol).toInt(),
    );

    final message = Message(instructions: [instruction]).compile(recentBlockhash: blockhash, feePayer: signer);

    final signedTx = SignedTx(
      compiledMessage: message,
      signatures: [Signature(List.filled(64, 0), publicKey: signer)],
    );

    final serializeTx = Uint8List.fromList(signedTx.toByteArray().toList());
    final signResult = await mwaClient.signTransactions(transactions: [serializeTx]);

    if (signResult.signedPayloads.isEmpty) {
      throw Exception("No signed payloads were returned");
    }

    final signature = await client.rpcClient.sendTransaction(
      base64.encode(signResult.signedPayloads[0]),
      preflightCommitment: Commitment.confirmed,
    );

    print('$_logPrefix 💰🤖 ✅ SOL Transferred Successfully: $signature');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ SOL Transferred: $signature")));
    }
    await scenario.close();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Solana Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ValueListenableBuilder<WalletState>(
          valueListenable: _walletManager.stateNotifier,
          builder: (context, walletState, child) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Connection Section
                  _buildConnectionSection(walletState),

                  const SizedBox(height: 20),

                  // Balance Section
                  if (walletState.isConnected) _buildBalanceSection(walletState),

                  const SizedBox(height: 20),

                  // Transaction Section
                  if (walletState.isConnected) _buildTransactionSection(walletState),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildConnectionSection(WalletState walletState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Wallet Connection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            ElevatedButton(
              onPressed: walletState.isConnecting
                  ? null
                  : () {
                      try{
                        print('$_logPrefix 🎯 Connect/Disconnect button pressed');
                        print('$_logPrefix 🎯 Current state: Connected=${walletState.isConnected}');

                        if (walletState.isConnected) {
                          print('$_logPrefix 🎯 Disconnecting wallet...');
                          _walletManager.disconnect();
                          authResult = null; // Clear Android auth result
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
                      }catch (e, st) {
                        print('$_logPrefix ❌ Error during connection: $e');
                        print('$_logPrefix ❌ Error during connection st: $st');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Connection error: $e")));
                        }
                      }
                    },
              child: walletState.isConnecting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 8),
                        Text('Connecting...'),
                      ],
                    )
                  : Text(walletState.isConnected ? 'Disconnect Wallet' : 'Connect Wallet'),
            ),

            const SizedBox(height: 12),

            // Platform indicator
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
              child: Text(
                'Platform: ${Platform.isAndroid ? "Android (MWA)" : "iOS (Deep Links)"}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                textAlign: TextAlign.center,
              ),
            ),

            // Wallet Info
            if (walletState.isConnected && walletState.publicKey != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connected: ${walletState.accountLabel ?? 'Wallet'}',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      'Address: ${walletState.publicKey}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              )
            else if (!walletState.isConnected && !walletState.isConnecting)
              const Text(
                'Please connect your wallet to continue',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),

            // Error Display
            if (walletState.error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                child: Text('Error: ${walletState.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceSection(WalletState walletState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Wallet Balances', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: walletState.isLoadingBalances ? null : _walletManager.fetchAllBalances,
                  icon: walletState.isLoadingBalances
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh, size: 16),
                  label: Text(walletState.isLoadingBalances ? 'Loading...' : 'Refresh'),
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // SOL Balance
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.account_balance_wallet, color: Colors.blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Solana (SOL)', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          walletState.solBalance != null
                              ? '${walletState.solBalance!.toStringAsFixed(6)} SOL'
                              : 'Click refresh to load',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // SPL Tokens
            if (walletState.tokenBalances.isNotEmpty) ...[
              const Text('SPL Tokens', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...walletState.tokenBalances.map((token) => _buildTokenItem(token)),
            ] else if (walletState.solBalance != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                child: const Text(
                  'No SPL tokens found',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTokenItem(TokenBalance token) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Colors.purple.shade100, borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.token, color: Colors.purple, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(token.symbol ?? 'Unknown Token', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  'Balance: ${token.balance.toStringAsFixed(token.decimals)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                Text(
                  'Mint: ${token.mintAddress.substring(0, 8)}...${token.mintAddress.substring(token.mintAddress.length - 8)}',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionSection(WalletState walletState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: walletState.isConnected ? sendSolana : null,
                    child: const Text('Send SOL'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: walletState.isConnected
                        ? () {
                            if (mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(const SnackBar(content: Text("SPL token sending not implemented yet")));
                            }
                          }
                        : null,
                    child: const Text('Send Tokens'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
