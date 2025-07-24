// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solana/base58.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'unified_wallet_connector.dart';
import 'wallet_model.dart';
import 'android_wallet_helper.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solana Wallet Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
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

  // Controllers for input fields
  final TextEditingController _solAmountController = TextEditingController(text: '0.01');
  final TextEditingController _receiverController = TextEditingController(
      text: '9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ'
  );
  final TextEditingController _messageController = TextEditingController(text: 'Hello Solana!');
  final TextEditingController _tokenMintController = TextEditingController();
  final TextEditingController _tokenAmountController = TextEditingController(text: '1.0');

  // Solana client and managers
  late SolanaClient client;
  late UnifiedWalletManager _walletManager;
  late AndroidWalletHelper _androidHelper;

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

    _androidHelper = AndroidWalletHelper(
      client: client,
      walletManager: _walletManager,
    );
    print('$_logPrefix 🤖 Android helper initialized');

    // Start periodic connection validation
    _startPeriodicValidation();

    print('$_logPrefix ✅ Initialization complete');
  }

  @override
  void dispose() {
    print('$_logPrefix 🗑️ Disposing widget...');
    _solAmountController.dispose();
    _receiverController.dispose();
    _messageController.dispose();
    _tokenMintController.dispose();
    _tokenAmountController.dispose();
    _walletManager.dispose();
    super.dispose();
  }

  /// Start periodic connection validation
  void _startPeriodicValidation() {
    print('$_logPrefix 🔄 Starting periodic validation timer...');
    // Validate connection every 30 seconds
    Stream.periodic(const Duration(seconds: 30)).listen((_) {
      if (mounted) {
        _androidHelper.validateConnectionPeriodically();
      }
    });
  }

  // ========== CONNECTION METHODS ==========

  Future<void> connectWalletAndroid() async {
    print('$_logPrefix 🤖 Starting Android wallet connection...');
    try {
      await _androidHelper.connectWallet();
      print('$_logPrefix 🤖 ✅ Android connection successful');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Wallet connected successfully!")),
        );
      }
    } catch (e) {
      print('$_logPrefix 🤖 ❌ Android wallet connection error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Connection failed: $e")),
        );
      }
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
                leading: const Icon(Icons.account_balance_wallet, color: Colors.purple),
                title: const Text('Phantom'),
                subtitle: const Text('Popular Solana wallet'),
                onTap: () async {
                  Navigator.of(context).pop();
                  try {
                    await _walletManager.connectWallet(WalletType.phantom);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to connect to Phantom: $e")),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet, color: Colors.orange),
                title: const Text('Solflare'),
                subtitle: const Text('Feature-rich Solana wallet'),
                onTap: () async {
                  Navigator.of(context).pop();
                  try {
                    await _walletManager.connectWallet(WalletType.solflare);
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Failed to connect to Solflare: $e")),
                      );
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

  // ========== TRANSACTION METHODS ==========

  Future<void> sendSolana() async {
    final amount = double.tryParse(_solAmountController.text) ?? 0.01;
    final receiver = _receiverController.text.trim();

    if (receiver.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter receiver address")),
      );
      return;
    }

    try {
      String signature;
      if (Platform.isAndroid) {
        signature = await _androidHelper.sendSolTransaction(
          amount: amount,
          receiverAddress: receiver,
        );
      } else {
        throw Exception("iOS transactions not yet implemented");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ SOL sent! Signature: ${signature.substring(0, 8)}...")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Failed to send SOL: $e")),
        );
      }
    }
  }

  Future<void> sendSplToken() async {
    final tokenMint = _tokenMintController.text.trim();
    final amount = double.tryParse(_tokenAmountController.text) ?? 1.0;
    final receiver = _receiverController.text.trim();

    if (tokenMint.isEmpty || receiver.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in all token transfer fields")),
      );
      return;
    }

    try {
      String signature;
      if (Platform.isAndroid) {
        signature = await _androidHelper.sendSplToken(
          tokenMintAddress: tokenMint,
          receiverAddress: receiver,
          amount: amount,
          decimals: 6, // Default to 6 decimals, should be fetched from token metadata
        );
      } else {
        throw Exception("iOS SPL token transactions not yet implemented");
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ SPL Token sent! Signature: ${signature.substring(0, 8)}...")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Failed to send SPL token: $e")),
        );
      }
    }
  }

  Future<void> signMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a message to sign")),
      );
      return;
    }

    try {
      String signature;
      if (Platform.isAndroid) {
        signature = await _androidHelper.signMessage(message);
      } else {
        throw Exception("iOS message signing not yet implemented");
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Message Signed'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Message:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(message),
                const SizedBox(height: 16),
                const Text('Signature:', style: TextStyle(fontWeight: FontWeight.bold)),
                SelectableText(
                  signature,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: signature));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Signature copied to clipboard")),
                  );
                },
                child: const Text('Copy'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Failed to sign message: $e")),
        );
      }
    }
  }

  Future<void> requestAirdrop() async {
    try {
      final walletState = _walletManager.stateNotifier.value;
      if (!walletState.isConnected || walletState.publicKey == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Wallet not connected")),
        );
        return;
      }

      print('$_logPrefix 💧 Requesting airdrop...');
      final signature = await client.rpcClient.requestAirdrop(
        walletState.publicKey!,
        lamportsPerSol, // 1 SOL
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Airdrop requested! Signature: ${signature.substring(0, 8)}...")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Airdrop failed: $e")),
        );
      }
    }
  }

  void showConnectionInfo() {
    final info = _androidHelper.connectionInfo;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: info.entries.map((entry) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('${entry.key}: ${entry.value}'),
            )).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solana Wallet Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: showConnectionInfo,
            tooltip: 'Connection Info',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ValueListenableBuilder(
          valueListenable: _walletManager.stateNotifier,
          builder: (context, walletState, child) {
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConnectionSection(walletState),
                  const SizedBox(height: 20),
                  if (walletState.isConnected) _buildBalanceSection(walletState),
                  const SizedBox(height: 20),
                  if (walletState.isConnected) _buildTransactionSection(walletState),
                  const SizedBox(height: 20),
                  if (walletState.isConnected) _buildAdvancedSection(walletState),
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
            const Text(
              'Wallet Connection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: walletState.isConnecting ? null : () {
                if (walletState.isConnected) {
                  _walletManager.disconnect();
                  _androidHelper.disconnect(reason: 'User requested disconnect');
                } else {
                  if (Platform.isAndroid) {
                    connectWalletAndroid();
                  } else if (Platform.isIOS) {
                    _showWalletSelectionDialog();
                  }
                }
              },
              icon: walletState.isConnecting
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : Icon(walletState.isConnected ? Icons.link_off : Icons.link),
              label: Text(
                walletState.isConnecting
                    ? 'Connecting...'
                    : walletState.isConnected
                    ? 'Disconnect Wallet'
                    : 'Connect Wallet',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Platform: ${Platform.isAndroid ? "Android (MWA)" : "iOS (Deep Links)"}',
                style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                textAlign: TextAlign.center,
              ),
            ),
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
            if (walletState.error != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Error: ${walletState.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
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
                const Text(
                  'Wallet Balances',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: requestAirdrop,
                      icon: const Icon(Icons.water_drop, size: 16),
                      label: const Text('Airdrop'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: walletState.isLoadingBalances ? null : _walletManager.fetchAllBalances,
                      icon: walletState.isLoadingBalances
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.refresh, size: 16),
                      label: Text(walletState.isLoadingBalances ? 'Loading...' : 'Refresh'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
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
            if (walletState.tokenBalances.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('SPL Tokens', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...walletState.tokenBalances.map((token) => _buildTokenItem(token)),
            ] else if (walletState.solBalance != null) ...[
              const SizedBox(height: 12),
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
            decoration: BoxDecoration(
              color: Colors.purple.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
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
            const Text('Send Transactions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // SOL Transfer Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Send SOL', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _solAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Amount (SOL)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _receiverController,
                          decoration: const InputDecoration(
                            labelText: 'Receiver Address',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: sendSolana,
                        child: const Text('Send'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // SPL Token Transfer Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Send SPL Token', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _tokenMintController,
                    decoration: const InputDecoration(
                      labelText: 'Token Mint Address',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tokenAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: sendSplToken,
                        child: const Text('Send Token'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // OPPI Token Transfer Section - NEW
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Send OPPI Token', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Mint: ${AndroidWalletHelper.oppiCoinMint}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (Platform.isAndroid) {
                        await _androidHelper.sendOppiTokens(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("iOS OPPI token sending not implemented")),
                        );
                      }
                    },
                    icon: const Icon(Icons.token, size: 16),
                    label: const Text('Send 1 OPPI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedSection(WalletState walletState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Advanced Functions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),

            // Message Signing Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sign Message', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            labelText: 'Message to Sign',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: signMessage,
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Sign'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Quick Actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _walletManager.fetchAllBalances(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh All'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                ),
                ElevatedButton.icon(
                  onPressed: showConnectionInfo,
                  icon: const Icon(Icons.info, size: 16),
                  label: const Text('Connection Info'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // Clear all input fields
                    _solAmountController.text = '0.01';
                    _tokenAmountController.text = '1.0';
                    _messageController.text = 'Hello Solana!';
                    _tokenMintController.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Input fields cleared")),
                    );
                  },
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear Inputs'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
