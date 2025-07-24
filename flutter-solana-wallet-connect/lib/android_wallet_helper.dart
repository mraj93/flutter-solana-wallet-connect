// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solana/base58.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'unified_wallet_connector.dart';

/// Helper class for managing Android Mobile Wallet Adapter (MWA) connections
/// Handles persistent connections, app existence validation, and transaction processing
class AndroidWalletHelper {
  static const String _logPrefix = '🤖 [AndroidHelper]';

  // Token program constants
  static const String oppiCoinMint = 'FuY29UVevrasnLAimZcVHKsVxsZNLWwy7FBG2rHfBfic';

  // Persistence keys for SharedPreferences
  static const String _keyIsConnected = 'android_wallet_connected';
  static const String _keyPublicKey = 'android_wallet_public_key';
  static const String _keyAccountLabel = 'android_wallet_account_label';
  static const String _keyAuthToken = 'android_wallet_auth_token';
  static const String _keyWalletPackage = 'android_wallet_package';

  // MWA components
  LocalAssociationScenario? scenario;
  MobileWalletAdapterClient? mwaClient;
  AuthorizationResult? authResult;

  // Dependencies
  final SolanaClient client;
  final UnifiedWalletManager walletManager;

  // State management
  bool _isConnected = false;
  String? _cachedPublicKey;
  String? _cachedAccountLabel;
  String? _cachedAuthToken;
  String? _walletPackageName;
  Timer? _healthMonitorTimer;

  AndroidWalletHelper({required this.client, required this.walletManager}) {
    print('$_logPrefix 🏗️ Initializing AndroidWalletHelper...');
    _initializeFromStorage();
  }

  /// Initialize helper with stored connection data
  Future<void> _initializeFromStorage() async {
    try {
      print('$_logPrefix 📱 Loading persistent connection data...');
      final prefs = await SharedPreferences.getInstance();

      _isConnected = prefs.getBool(_keyIsConnected) ?? false;
      _cachedPublicKey = prefs.getString(_keyPublicKey);
      _cachedAccountLabel = prefs.getString(_keyAccountLabel);
      _cachedAuthToken = prefs.getString(_keyAuthToken);
      _walletPackageName = prefs.getString(_keyWalletPackage);

      print('$_logPrefix 📱 Loaded connection state: connected=$_isConnected');
      print('$_logPrefix 📱 Cached public key: ${_cachedPublicKey?.substring(0, 8)}...');
      print('$_logPrefix 📱 Wallet package: $_walletPackageName');

      // Validate stored connection if exists
      if (_isConnected && _cachedPublicKey != null) {
        await _validateStoredConnection();
      }

      print('$_logPrefix 📱 ✅ Initialization from storage complete');
    } catch (e) {
      print('$_logPrefix 📱 ❌ Failed to initialize from storage: $e');
      await _clearStoredConnection();
    }
  }

  /// Validate if the stored wallet connection is still valid
  Future<void> _validateStoredConnection() async {
    print('$_logPrefix 🔍 Validating stored wallet connection...');

    try {
      // Check if wallet app still exists
      if (_walletPackageName != null) {
        final appExists = await _checkWalletAppExists(_walletPackageName!);
        if (!appExists) {
          print('$_logPrefix 🔍 ❌ Wallet app no longer exists, disconnecting...');
          await disconnect(reason: 'Wallet app uninstalled');
          return;
        }
        print('$_logPrefix 🔍 ✅ Wallet app still exists');
      }

      // Try to restore auth result from cached data
      if (_cachedPublicKey != null && _cachedAuthToken != null) {
        print('$_logPrefix 🔍 Attempting to restore auth result...');

        try {
          final publicKeyBytes = base58decode(_cachedPublicKey!);
          authResult = AuthorizationResult(
            publicKey: Uint8List.fromList(publicKeyBytes),
            accountLabel: _cachedAccountLabel,
            authToken: _cachedAuthToken!,
            walletUriBase: null,
          );

          // Update wallet manager with restored connection
          walletManager.setAndroidConnection(_cachedPublicKey!, authResult!);
          print('$_logPrefix 🔍 ✅ Successfully restored wallet connection');

          // Test connection with a simple operation
          await _testConnection();

          // Start health monitoring if connection is restored
          if (_isConnected) {
            startConnectionHealthMonitoring();
          }
        } catch (e) {
          print('$_logPrefix 🔍 ❌ Failed to create auth result: $e');
          await disconnect(reason: 'Failed to restore auth result');
        }
      }
    } catch (e) {
      print('$_logPrefix 🔍 ❌ Connection validation failed: $e');
      await disconnect(reason: 'Connection validation failed');
    }
  }

  /// Test if the current connection is working
  Future<bool> _testConnection() async {
    print('$_logPrefix 🧪 Testing wallet connection...');

    try {
      if (authResult == null) {
        print('$_logPrefix 🧪 ❌ No auth result to test');
        return false;
      }

      // Try to get account info as a connection test
      final publicKey = Ed25519HDPublicKey(authResult!.publicKey);
      final accountInfo = await client.rpcClient
          .getAccountInfo(publicKey.toBase58(), commitment: Commitment.confirmed)
          .timeout(const Duration(seconds: 10));

      print('$_logPrefix 🧪 ✅ Connection test successful');
      return true;
    } catch (e) {
      print('$_logPrefix 🧪 ❌ Connection test failed: $e');
      return false;
    }
  }

  /// Check if current session is still valid before transactions
  Future<bool> _validateSession() async {
    print('$_logPrefix 🔐 Validating current session...');

    try {
      if (authResult == null) {
        print('$_logPrefix 🔐 ❌ No auth result found');
        return false;
      }

      // Test with a simple RPC call to validate connection
      final publicKey = Ed25519HDPublicKey(authResult!.publicKey);
      await client.rpcClient
          .getAccountInfo(publicKey.toBase58(), commitment: Commitment.confirmed)
          .timeout(const Duration(seconds: 5));

      print('$_logPrefix 🔐 ✅ Session validation successful');
      return true;
    } catch (e) {
      print('$_logPrefix 🔐 ❌ Session validation failed: $e');
      return false;
    }
  }

  /// Auto-reauthorize if session is expired
  Future<bool> _ensureValidSession(MobileWalletAdapterClient client) async {
    print('$_logPrefix 🔄 Ensuring valid session...');

    // First check if we have basic auth
    if (authResult == null) {
      print('$_logPrefix 🔄 ❌ No auth result available');
      return false;
    }

    // Try reauthorization with better error handling
    try {
      final reauthorized = await client
          .reauthorize(
            identityUri: Uri.parse("https://solana-demo-app.com"),
            iconUri: Uri.parse("favicon.ico"),
            identityName: "Solana Demo App",
            authToken: authResult!.authToken,
          )
          .timeout(const Duration(seconds: 15)); // Add timeout

      if (reauthorized?.publicKey != null) {
        print('$_logPrefix 🔄 ✅ Session reauthorization successful');
        return true;
      } else {
        print('$_logPrefix 🔄 ❌ Reauthorization returned null');
        return false;
      }
    } catch (e) {
      print('$_logPrefix 🔄 ❌ Reauthorization failed: $e');

      // If reauth failed, mark as disconnected
      if (e.toString().contains('timeout') || e.toString().contains('cancelled')) {
        print('$_logPrefix 🔄 🔌 Marking connection as expired due to timeout/cancellation');
        await disconnect(reason: 'Session timeout or user cancelled');
      }

      return false;
    }
  }

  /// Monitor connection health and auto-disconnect if needed
  void startConnectionHealthMonitoring() {
    print('$_logPrefix 🏥 Starting connection health monitoring...');

    // Cancel existing timer if any
    _healthMonitorTimer?.cancel();

    _healthMonitorTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (!_isConnected) {
        print('$_logPrefix 🏥 Connection not active, stopping health monitoring');
        timer.cancel();
        return;
      }

      try {
        final isHealthy = await _validateSession();
        if (!isHealthy) {
          print('$_logPrefix 🏥 Connection health check failed, disconnecting...');
          await disconnect(reason: 'Connection health check failed');
          timer.cancel();
        } else {
          print('$_logPrefix 🏥 ✅ Connection health check passed');
        }
      } catch (e) {
        print('$_logPrefix 🏥 Health check error: $e');
      }
    });
  }

  /// Check if a wallet app exists on the device
  Future<bool> _checkWalletAppExists(String packageName) async {
    try {
      print('$_logPrefix 📦 Checking if wallet app exists: $packageName');

      // Use platform channel to check if app is installed
      const platform = MethodChannel('wallet_app_checker');
      final result = await platform.invokeMethod('isAppInstalled', packageName);

      print('$_logPrefix 📦 App exists check result: $result');
      return result == true;
    } catch (e) {
      print('$_logPrefix 📦 ❌ Failed to check app existence: $e');
      // Assume app exists if we can't check (fallback)
      return true;
    }
  }

  /// Connect to Android wallet using Mobile Wallet Adapter
  /// Maintains persistent connection until user explicitly disconnects
  Future<void> connectWallet() async {
    print('$_logPrefix 🔌 Starting Android wallet connection...');

    try {
      // Check if already connected and valid
      if (_isConnected && authResult != null) {
        print('$_logPrefix 🔌 ⚡ Already connected, testing existing connection...');
        final isValid = await _testConnection();
        if (isValid) {
          print('$_logPrefix 🔌 ✅ Existing connection is valid, reusing...');
          return;
        } else {
          print('$_logPrefix 🔌 ⚠️ Existing connection invalid, creating new...');
          await _clearStoredConnection();
        }
      }

      print('$_logPrefix 🔌 Creating new LocalAssociationScenario...');
      scenario = await LocalAssociationScenario.create();

      print('$_logPrefix 🔌 Starting wallet selection activity...');
      scenario!.startActivityForResult(null).ignore();

      print('$_logPrefix 🔌 Starting MWA client...');
      mwaClient = await scenario!.start();

      print('$_logPrefix 🔌 Requesting wallet authorization...');
      authResult = await mwaClient!.authorize(
        identityName: 'Solana Demo App',
        identityUri: Uri.parse("https://solana-demo-app.com"),
        iconUri: Uri.parse("favicon.ico"),
        cluster: 'devnet',
      );

      if (authResult?.publicKey != null) {
        final publicKeyBase58 = base58encode(authResult!.publicKey.toList());
        print('$_logPrefix 🔌 ✅ Authorization successful!');
        print('$_logPrefix 🔌 📋 Public key: $publicKeyBase58');
        print('$_logPrefix 🔌 🏷️ Account label: ${authResult!.accountLabel}');
        print('$_logPrefix 🔌 🔑 Auth token length: ${authResult!.authToken.length}');

        // Store connection data for persistence
        await _storeConnectionData(publicKeyBase58);

        // Update the unified wallet manager
        walletManager.setAndroidConnection(publicKeyBase58, authResult!);

        _isConnected = true;

        // Start health monitoring
        startConnectionHealthMonitoring();

        print('$_logPrefix 🔌 💾 Connection data persisted successfully');
      } else {
        print('$_logPrefix 🔌 ❌ Authorization failed - no public key received');
        throw Exception('Authorization failed - no public key received');
      }

      print('$_logPrefix 🔌 🔄 Closing initial scenario...');
      await scenario?.close();
      print('$_logPrefix 🔌 ✅ Android connection process complete');
    } catch (e) {
      print('$_logPrefix 🔌 ❌ Android wallet connection error: $e');
      print('$_logPrefix 🔌 📍 Stack trace: ${StackTrace.current}');

      // Clean up on failure
      await _clearStoredConnection();
      await scenario?.close();

      rethrow;
    }
  }

  /// Store connection data for persistence
  Future<void> _storeConnectionData(String publicKey) async {
    try {
      print('$_logPrefix 💾 Storing connection data...');
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(_keyIsConnected, true);
      await prefs.setString(_keyPublicKey, publicKey);
      await prefs.setString(_keyAccountLabel, authResult!.accountLabel ?? '');
      await prefs.setString(_keyAuthToken, authResult!.authToken);

      // Try to detect wallet package name (this would need platform-specific implementation)
      _walletPackageName = await _detectWalletPackage();
      if (_walletPackageName != null) {
        await prefs.setString(_keyWalletPackage, _walletPackageName!);
      }

      _cachedPublicKey = publicKey;
      _cachedAccountLabel = authResult!.accountLabel;
      _cachedAuthToken = authResult!.authToken;

      print('$_logPrefix 💾 ✅ Connection data stored successfully');
    } catch (e) {
      print('$_logPrefix 💾 ❌ Failed to store connection data: $e');
    }
  }

  /// Detect which wallet package was used for connection
  Future<String?> _detectWalletPackage() async {
    try {
      print('$_logPrefix 🔍 Detecting wallet package...');
      // This would need platform-specific implementation
      // For now, return a placeholder
      return 'com.phantom.app'; // Placeholder
    } catch (e) {
      print('$_logPrefix 🔍 ❌ Failed to detect wallet package: $e');
      return null;
    }
  }

  /// Send SOL transaction with enhanced session management
  Future<String> sendSolTransaction({required double amount, required String receiverAddress}) async {
    print('$_logPrefix 💰 Starting SOL transfer...');
    print('$_logPrefix 💰 📊 Amount: $amount SOL');
    print('$_logPrefix 💰 📍 To: $receiverAddress');

    if (!_isConnected || authResult == null) {
      print('$_logPrefix 💰 ❌ Wallet not connected');
      throw Exception('Wallet not connected. Please connect first.');
    }

    // Validate session before starting transaction
    if (!await _validateSession()) {
      print('$_logPrefix 💰 ⚠️ Session appears invalid, attempting to reconnect...');
      throw Exception('Session expired. Please reconnect your wallet.');
    }

    LocalAssociationScenario? transactionScenario;

    try {
      final receiver = Ed25519HDPublicKey.fromBase58(receiverAddress);
      print('$_logPrefix 💰 ✅ Receiver address validated');

      // Create new scenario for transaction with timeout
      print('$_logPrefix 💰 🔄 Creating transaction scenario...');
      transactionScenario = await LocalAssociationScenario.create().timeout(const Duration(seconds: 10));

      transactionScenario.startActivityForResult(null).ignore();

      // Add timeout for client start
      final transactionClient = await transactionScenario.start().timeout(const Duration(seconds: 15));

      // Enhanced reauthorization
      print('$_logPrefix 💰 🔐 Ensuring valid session for transaction...');
      if (!await _ensureValidSession(transactionClient)) {
        await transactionScenario.close();
        throw Exception('Failed to authorize for transaction. Please try connecting again.');
      }

      // Build transaction
      print('$_logPrefix 💰 🏗️ Building transaction...');
      final signer = Ed25519HDPublicKey(authResult!.publicKey);
      final blockhash = (await client.rpcClient.getLatestBlockhash()).value.blockhash;
      print('$_logPrefix 💰 📦 Latest blockhash: $blockhash');

      final instruction = SystemInstruction.transfer(
        fundingAccount: signer,
        recipientAccount: receiver,
        lamports: (amount * lamportsPerSol).toInt(),
      );
      print('$_logPrefix 💰 💸 Lamports to transfer: ${(amount * lamportsPerSol).toInt()}');

      final message = Message(instructions: [instruction]).compile(recentBlockhash: blockhash, feePayer: signer);

      final signedTx = SignedTx(
        compiledMessage: message,
        signatures: [Signature(List.filled(64, 0), publicKey: signer)],
      );

      // Sign transaction
      print('$_logPrefix 💰 ✍️ Signing transaction...');
      final serializeTx = Uint8List.fromList(signedTx.toByteArray().toList());

      // Add timeout for signing
      final signResult = await transactionClient
          .signTransactions(transactions: [serializeTx])
          .timeout(const Duration(seconds: 30)); // Give user time to approve

      if (signResult.signedPayloads.isEmpty) {
        throw Exception("No signed payloads returned from wallet");
      }
      print('$_logPrefix 💰 ✅ Transaction signed successfully');

      // Send transaction
      print('$_logPrefix 💰 📡 Broadcasting transaction...');
      final signature = await client.rpcClient.sendTransaction(
        base64.encode(signResult.signedPayloads[0]),
        preflightCommitment: Commitment.confirmed,
      );

      print('$_logPrefix 💰 ✅ SOL transferred successfully!');
      print('$_logPrefix 💰 🔗 Transaction signature: $signature');

      await transactionScenario.close();
      return signature;
    } catch (e) {
      print('$_logPrefix 💰 ❌ SOL transfer failed: $e');

      // Enhanced error handling for different scenarios
      if (e.toString().contains('timeout')) {
        print('$_logPrefix 💰 ⏱️ Transaction timed out');
        throw Exception('Transaction timed out. Please try again.');
      } else if (e.toString().contains('cancelled') || e.toString().contains('user')) {
        print('$_logPrefix 💰 🚫 User cancelled transaction');
        throw Exception('Transaction cancelled by user.');
      } else if (e.toString().contains('unauthorized') || e.toString().contains('reauthorize')) {
        print('$_logPrefix 💰 🔐 Authorization issue');
        await disconnect(reason: 'Authorization expired');
        throw Exception('Session expired. Please reconnect your wallet.');
      }

      await transactionScenario?.close();
      rethrow;
    }
  }

  /// Send SPL Token transaction - ENHANCED VERSION
  Future<String> sendSplToken({
    required String tokenMintAddress,
    required String receiverAddress,
    required double amount,
    int? decimals, // Make decimals optional
  }) async {
    print('$_logPrefix 🪙 Starting SPL token transfer...');
    print('$_logPrefix 🪙 🏷️ Token mint: $tokenMintAddress');
    print('$_logPrefix 🪙 📊 Amount: $amount');
    print('$_logPrefix 🪙 📍 To: $receiverAddress');

    if (!_isConnected || authResult == null) {
      throw Exception('Wallet not connected. Please connect first.');
    }

    // Validate session before starting transaction
    if (!await _validateSession()) {
      throw Exception('Session expired. Please reconnect your wallet.');
    }

    LocalAssociationScenario? tokenScenario;

    try {
      // Get token decimals if not provided
      final tokenDecimals = decimals ?? lamportsPerSol;
      print('$_logPrefix 🪙 🔢 Using decimals: $tokenDecimals');

      // Create new scenario for transaction
      print('$_logPrefix 🪙 🔄 Creating transaction scenario...');
      tokenScenario = await LocalAssociationScenario.create().timeout(const Duration(seconds: 10));

      tokenScenario.startActivityForResult(null).ignore();

      final transactionClient = await tokenScenario.start().timeout(const Duration(seconds: 15));

      // Enhanced reauthorization
      print('$_logPrefix 🪙 🔐 Ensuring valid session for transaction...');
      if (!await _ensureValidSession(transactionClient)) {
        await tokenScenario.close();
        throw Exception('Failed to authorize for SPL token transaction');
      }

      // Build SPL token transfer instruction
      final signer = Ed25519HDPublicKey(authResult!.publicKey);
      final receiver = Ed25519HDPublicKey.fromBase58(receiverAddress);
      final mint = Ed25519HDPublicKey.fromBase58(tokenMintAddress);

      print('$_logPrefix 🪙 🔍 Finding associated token accounts...');

      final senderTokenAccount = await findAssociatedTokenAddress(owner: signer, mint: mint);
      final receiverTokenAccount = await findAssociatedTokenAddress(owner: receiver, mint: mint);

      print('$_logPrefix 🪙 📍 Sender ATA: ${senderTokenAccount.toBase58()}');
      print('$_logPrefix 🪙 📍 Receiver ATA: ${receiverTokenAccount.toBase58()}');

      final blockhashResponse = await client.rpcClient.getLatestBlockhash().timeout(const Duration(seconds: 10));
      final blockhash = blockhashResponse.value.blockhash;
      print('$_logPrefix 🪙 📦 Latest blockhash: $blockhash');

      final instructions = <Instruction>[];

      // Check if receiver ATA exists, create if not
      try {
        final receiverAccountInfo = await client.rpcClient.getAccountInfo(
          receiverTokenAccount.toBase58(),
          commitment: Commitment.confirmed,
        );

        if (receiverAccountInfo.value == null) {
          print('$_logPrefix 🪙 🏗️ Creating receiver ATA...');
          final createATAInstruction = AssociatedTokenAccountInstruction.createAccount(
            funder: signer,
            address: receiverTokenAccount,
            owner: receiver,
            mint: mint,
          );
          instructions.add(createATAInstruction);
        }
      } catch (e) {
        print('$_logPrefix 🪙 ⚠️ Could not check receiver ATA, will attempt to create: $e');
        final createATAInstruction = AssociatedTokenAccountInstruction.createAccount(
          funder: signer,
          address: receiverTokenAccount,
          owner: receiver,
          mint: mint,
        );
        instructions.add(createATAInstruction);
      }

      // Create transfer instruction with proper amount calculation
      print('$_logPrefix 🪙 💸 Creating transfer instruction...');
      final transferAmount = (amount * (1 << tokenDecimals)).toInt(); // Use bit shift for efficiency
      print('$_logPrefix 🪙 💸 Transfer amount (raw): $transferAmount');

      final transferInstruction = TokenInstruction.transfer(
        source: senderTokenAccount,
        destination: receiverTokenAccount,
        owner: signer,
        amount: transferAmount,
      );
      instructions.add(transferInstruction);

      print('$_logPrefix 🪙 📋 Total instructions: ${instructions.length}');

      final message = Message(instructions: instructions).compile(recentBlockhash: blockhash, feePayer: signer);

      final signedTx = SignedTx(
        compiledMessage: message,
        signatures: [Signature(List.filled(64, 0), publicKey: signer)],
      );

      // Check transaction size
      final serializeTx = Uint8List.fromList(signedTx.toByteArray().toList());
      print('$_logPrefix 🪙 📏 Transaction size: ${serializeTx.length} bytes');

      if (serializeTx.length > 1232) {
        throw Exception('Transaction too large: ${serializeTx.length} bytes');
      }

      // Sign and send with enhanced timeout handling
      print('$_logPrefix 🪙 ✍️ Signing transaction...');
      final signResult = await transactionClient
          .signTransactions(transactions: [serializeTx])
          .timeout(const Duration(seconds: 45)); // Extended timeout

      if (signResult.signedPayloads.isEmpty) {
        throw Exception("No signed payloads returned");
      }

      print('$_logPrefix 🪙 📡 Broadcasting transaction...');
      final signature = await client.rpcClient.sendTransaction(
        base64.encode(signResult.signedPayloads[0]),
        preflightCommitment: Commitment.confirmed,
      );

      print('$_logPrefix 🪙 ✅ SPL token transferred successfully: $signature');
      await tokenScenario.close();
      return signature;
    } on TimeoutException catch (e) {
      print('$_logPrefix 🪙 ⏱️ Operation timed out: $e');
      await tokenScenario?.close();
      throw Exception('Transaction timed out. Please try again.');
    } catch (e) {
      print('$_logPrefix 🪙 ❌ SPL token transfer failed: $e');

      if (e.toString().contains('cancelled') || e.toString().contains('user')) {
        throw Exception('Transaction cancelled by user.');
      } else if (e.toString().contains('unauthorized') || e.toString().contains('session')) {
        await disconnect(reason: 'Session expired during transaction');
        throw Exception('Session expired. Please reconnect your wallet.');
      }

      await tokenScenario?.close();
      rethrow;
    }
  }

  /// Send OPPI tokens with enhanced error handling
  Future<void> sendOppiTokens(BuildContext context) async {
    print('$_logPrefix 🟡 Starting OPPI token transfer...');
    final snackBar = ScaffoldMessenger.of(context);
    LocalAssociationScenario? oppiScenario;

    try {
      if (!isConnected || authResult == null) {
        snackBar.showSnackBar(const SnackBar(content: Text("You are not authorized")));
        return;
      }

      // Session validation
      if (!await _validateSession()) {
        snackBar.showSnackBar(
          const SnackBar(
            content: Text("Session expired. Please reconnect your wallet."),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      const amount = 1;
      final tokenMint = Ed25519HDPublicKey.fromBase58(oppiCoinMint);
      final receiverWallet = Ed25519HDPublicKey.fromBase58('Gqknxr7kBQJzxkiyxRh63sCdbpo3QtpTGSxei3VUbTkY');

      print('$_logPrefix 🟡 🔄 Creating transaction scenario...');

      // Timeout for scenario creation
      oppiScenario = await LocalAssociationScenario.create().timeout(const Duration(seconds: 10));

      oppiScenario.startActivityForResult(null).ignore();

      // Timeout for client start
      print('$_logPrefix 🟡 ⏳ Waiting for wallet app selection...');
      final mwaClient = await oppiScenario.start().timeout(
        const Duration(seconds: 20), // Give user time to select app
        onTimeout: () {
          print('$_logPrefix 🟡 ⏱️ Wallet selection timed out');
          throw TimeoutException('Wallet selection timed out', const Duration(seconds: 20));
        },
      );

      // Enhanced session validation
      if (!await _ensureValidSession(mwaClient)) {
        snackBar.showSnackBar(const SnackBar(content: Text("Authorization failed. Please reconnect.")));
        await oppiScenario.close();
        return;
      }

      final signer = Ed25519HDPublicKey(authResult!.publicKey);
      final blockhash = (await client.rpcClient.getLatestBlockhash()).value.blockhash;
      print('$_logPrefix 🟡 📦 Latest blockhash: $blockhash');

      final senderATA = await findAssociatedTokenAddress(owner: signer, mint: tokenMint);
      final receiverATA = await findAssociatedTokenAddress(owner: receiverWallet, mint: tokenMint);

      print('$_logPrefix 🟡 📍 Sender ATA: ${senderATA.toBase58()}');
      print('$_logPrefix 🟡 📍 Receiver ATA: ${receiverATA.toBase58()}');

      final instructions = <Instruction>[];
      final transferAmount = (amount * lamportsPerSol).toInt();
      print('$_logPrefix 🟡 💸 Transfer amount (raw): $transferAmount');

      final transferInstruction = TokenInstruction.transfer(
        source: senderATA,
        destination: receiverATA,
        owner: signer,
        amount: transferAmount,
      );
      instructions.add(transferInstruction);

      print('$_logPrefix 🟡 📋 Total instructions: ${instructions.length}');

      final message = Message(instructions: instructions).compile(recentBlockhash: blockhash, feePayer: signer);

      final signedTx = SignedTx(
        compiledMessage: message,
        signatures: [Signature(List.filled(64, 0), publicKey: signer)],
      );

      final serializedTx = Uint8List.fromList(signedTx.toByteArray().toList());
      print('$_logPrefix 🟡 📏 Transaction size: ${serializedTx.length} bytes');

      print('$_logPrefix 🟡 ✍️ Waiting for transaction approval...');

      // Extended timeout for user to approve transaction
      final signResult = await mwaClient
          .signTransactions(transactions: [serializedTx])
          .timeout(
            const Duration(seconds: 45), // Give user plenty of time
            onTimeout: () {
              print('$_logPrefix 🟡 ⏱️ Transaction approval timed out');
              throw TimeoutException('Transaction approval timed out', const Duration(seconds: 45));
            },
          );

      if (signResult.signedPayloads.isEmpty) {
        throw Exception("No signed payloads returned");
      }

      print('$_logPrefix 🟡 📡 Broadcasting transaction...');
      final txSignature = await client.rpcClient.sendTransaction(
        base64.encode(signResult.signedPayloads[0]),
        preflightCommitment: Commitment.confirmed,
      );

      print('$_logPrefix 🟡 ✅ OPPI token transfer successful: $txSignature');
      snackBar.showSnackBar(
        SnackBar(
          content: Text("✅ OPPI Token sent! Signature: ${txSignature.substring(0, 8)}..."),
          duration: const Duration(seconds: 5),
        ),
      );

      await oppiScenario.close();
    } on TimeoutException catch (e) {
      // Specific handling for timeout
      print('$_logPrefix 🟡 ⏱️ Operation timed out: $e');
      snackBar.showSnackBar(
        const SnackBar(content: Text("⏱️ Operation timed out. Please try again."), backgroundColor: Colors.orange),
      );
      await oppiScenario?.close();
    } catch (err) {
      print('$_logPrefix 🟡 ❌ Error in OPPI token transfer: $err');

      // Better error categorization
      String errorMessage;
      Color bgColor = Colors.red;

      if (err.toString().contains('cancelled') || err.toString().contains('user')) {
        errorMessage = "🚫 Transaction cancelled by user";
        bgColor = Colors.grey;
      } else if (err.toString().contains('timeout')) {
        errorMessage = "⏱️ Request timed out. Please try again.";
        bgColor = Colors.orange;
      } else if (err.toString().contains('insufficient')) {
        errorMessage = "💰 Insufficient OPPI token balance";
      } else if (err.toString().contains('unauthorized') || err.toString().contains('session')) {
        errorMessage = "🔐 Session expired. Please reconnect wallet.";
        // Auto-disconnect on session issues
        await disconnect(reason: 'Session expired during transaction');
      } else {
        errorMessage = "❌ Transfer failed: ${err.toString().split(':').last.trim()}";
      }

      snackBar.showSnackBar(
        SnackBar(content: Text(errorMessage), duration: const Duration(seconds: 5), backgroundColor: bgColor),
      );

      await oppiScenario?.close();
    }
  }

  /// Sign a message with the connected wallet - FIXED VERSION
  Future<String> signMessage(String message) async {
    print('$_logPrefix ✍️ Signing message...');
    print('$_logPrefix ✍️ 📝 Message: $message');

    if (!_isConnected || authResult == null) {
      throw Exception('Wallet not connected. Please connect first.');
    }

    // Validate session before signing
    if (!await _validateSession()) {
      throw Exception('Session expired. Please reconnect your wallet.');
    }

    LocalAssociationScenario? signScenario;

    try {
      print('$_logPrefix ✍️ 🔄 Creating signing scenario...');
      signScenario = await LocalAssociationScenario.create().timeout(const Duration(seconds: 10));

      signScenario.startActivityForResult(null).ignore();

      final signClient = await signScenario.start().timeout(const Duration(seconds: 15));

      print('$_logPrefix ✍️ 🔐 Ensuring valid session for signing...');
      if (!await _ensureValidSession(signClient)) {
        await signScenario.close();
        throw Exception('Failed to reauthorize for message signing');
      }

      final messageBytes = utf8.encode(message);

      print('$_logPrefix ✍️ ✍️ Requesting message signature...');
      // Use raw bytes for addresses parameter
      final signResult = await signClient
          .signMessages(
            addresses: [authResult!.publicKey], // Use raw bytes, not base58 string
            messages: [messageBytes],
          )
          .timeout(const Duration(seconds: 30));

      // Check for signed messages
      if (signResult.signedMessages.isEmpty) {
        throw Exception("No signed message returned");
      }

      // Get the signature from signed messages
      final signature = base64.encode(signResult.signedMessages[0].message.toList());
      print('$_logPrefix ✍️ ✅ Message signed successfully');

      await signScenario.close();
      return signature;
    } on TimeoutException catch (e) {
      print('$_logPrefix ✍️ ⏱️ Signing timed out: $e');
      await signScenario?.close();
      throw Exception('Message signing timed out. Please try again.');
    } catch (e) {
      print('$_logPrefix ✍️ ❌ Message signing failed: $e');

      if (e.toString().contains('cancelled') || e.toString().contains('user')) {
        throw Exception('Message signing cancelled by user.');
      } else if (e.toString().contains('unauthorized') || e.toString().contains('session')) {
        await disconnect(reason: 'Session expired during signing');
        throw Exception('Session expired. Please reconnect your wallet.');
      }

      await signScenario?.close();
      rethrow;
    }
  }

  /// Disconnect wallet and clear all stored data
  Future<void> disconnect({String? reason}) async {
    print('$_logPrefix 🔌 Disconnecting wallet...');
    if (reason != null) {
      print('$_logPrefix 🔌 📋 Reason: $reason');
    }

    try {
      // Cancel health monitoring
      _healthMonitorTimer?.cancel();
      _healthMonitorTimer = null;

      // Clear in-memory state
      authResult = null;
      _isConnected = false;
      _cachedPublicKey = null;
      _cachedAccountLabel = null;
      _cachedAuthToken = null;
      _walletPackageName = null;

      // Clear stored data
      await _clearStoredConnection();

      // Close any active scenarios
      await scenario?.close();
      scenario = null;
      mwaClient = null;

      // Update wallet manager
      walletManager.disconnect();

      print('$_logPrefix 🔌 ✅ Wallet disconnected successfully');
    } catch (e) {
      print('$_logPrefix 🔌 ❌ Error during disconnect: $e');
    }
  }

  /// Clear stored connection data
  Future<void> _clearStoredConnection() async {
    try {
      print('$_logPrefix 🗑️ Clearing stored connection data...');
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_keyIsConnected);
      await prefs.remove(_keyPublicKey);
      await prefs.remove(_keyAccountLabel);
      await prefs.remove(_keyAuthToken);
      await prefs.remove(_keyWalletPackage);

      print('$_logPrefix 🗑️ ✅ Stored connection data cleared');
    } catch (e) {
      print('$_logPrefix 🗑️ ❌ Failed to clear stored data: $e');
    }
  }

  /// Check connection status periodically
  Future<void> validateConnectionPeriodically() async {
    print('$_logPrefix 🔄 Starting periodic connection validation...');

    if (!_isConnected) {
      print('$_logPrefix 🔄 Not connected, skipping validation');
      return;
    }

    try {
      final isValid = await _testConnection();
      if (!isValid) {
        print('$_logPrefix 🔄 ⚠️ Connection validation failed, disconnecting...');
        await disconnect(reason: 'Periodic validation failed');
      } else {
        print('$_logPrefix 🔄 ✅ Connection validation successful');
      }
    } catch (e) {
      print('$_logPrefix 🔄 ❌ Validation error: $e');
    }
  }

  /// Clear the Android auth result
  void clearAuthResult() {
    authResult = null;
    _isConnected = false;
    _healthMonitorTimer?.cancel();
    print('$_logPrefix 🗑️ Android auth result cleared');
  }

  // Getters for connection state
  bool get isConnected => _isConnected && authResult?.publicKey != null;

  String? get publicKey =>
      _cachedPublicKey ?? (authResult?.publicKey != null ? base58encode(authResult!.publicKey.toList()) : null);

  String? get accountLabel => _cachedAccountLabel ?? authResult?.accountLabel;

  String? get walletPackageName => _walletPackageName;

  /// Get connection info for debugging
  Map<String, dynamic> get connectionInfo => {
    'isConnected': isConnected,
    'publicKey': publicKey,
    'accountLabel': accountLabel,
    'walletPackage': walletPackageName,
    'hasAuthResult': authResult != null,
    'authTokenLength': authResult?.authToken.length ?? 0,
    'healthMonitorActive': _healthMonitorTimer?.isActive ?? false,
  };
}
