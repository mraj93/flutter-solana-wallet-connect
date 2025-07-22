// ignore_for_file: avoid_print

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:test5/wallet_connector_logic.dart';
import 'package:test5/wallet_model.dart';
import 'package:url_launcher/url_launcher.dart';

class UnifiedWalletManager extends ChangeNotifier {
  static const String _logPrefix = '🔗 [WalletManager]';

  final PhantomConnector _phantomConnector = PhantomConnector();
  final SolflareConnector _solflareConnector = SolflareConnector();

  // ValueNotifier for reactive state management
  final ValueNotifier<WalletState> _stateNotifier = ValueNotifier<WalletState>(const WalletState());

  // Getters for accessing state
  ValueNotifier<WalletState> get stateNotifier => _stateNotifier;

  WalletState get state => _stateNotifier.value;

  bool get isConnected => state.isConnected;

  String? get publicKey => state.publicKey;

  WalletType? get currentWallet => state.walletType;

  bool get isConnecting => state.isConnecting;

  // Update state and notify listeners with logging
  void _updateState(WalletState newState) {
    final oldState = _stateNotifier.value;
    print('$_logPrefix State Update:');
    print(
      '  📊 Old State: Connected=${oldState.isConnected}, Wallet=${oldState.walletType}, Connecting=${oldState.isConnecting}',
    );
    print(
      '  📊 New State: Connected=${newState.isConnected}, Wallet=${newState.walletType}, Connecting=${newState.isConnecting}',
    );

    if (newState.publicKey != oldState.publicKey) {
      print('  🔑 Public Key Changed: ${newState.publicKey}');
    }

    if (newState.error != null) {
      print('  ❌ Error: ${newState.error}');
    }

    _stateNotifier.value = newState;
    notifyListeners();
    print('$_logPrefix State update complete, listeners notified');
  }

  Future<void> connectWallet(WalletType walletType) async {
    print('$_logPrefix Starting connection to ${walletType.name} wallet');

    try {
      // Set connecting state
      print('$_logPrefix Setting connecting state...');
      _updateState(state.copyWith(isConnecting: true, error: null));

      switch (walletType) {
        case WalletType.phantom:
          print('$_logPrefix Initiating Phantom connection...');
          await _connectPhantom();
          break;
        case WalletType.solflare:
          print('$_logPrefix Initiating Solflare connection...');
          await _connectSolflare();
          break;
      }

      print('$_logPrefix Connection attempt completed');
    } catch (e) {
      print('$_logPrefix ❌ Connection failed: $e');
      _updateState(state.copyWith(isConnecting: false, error: e.toString()));
      rethrow;
    }
  }

  Future<void> _connectPhantom() async {
    print('$_logPrefix 👻 Connecting to Phantom...');
    await _phantomConnector.connectPhantomWallet((pubkey) {
      print('$_logPrefix 👻 ✅ Phantom connection successful!');
      print('$_logPrefix 👻 Public Key received: $pubkey');
      _updateState(
        state.copyWith(
          isConnected: true,
          publicKey: pubkey,
          walletType: WalletType.phantom,
          accountLabel: 'Phantom',
          isConnecting: false,
          error: null,
        ),
      );
    });
  }

  Future<void> _connectSolflare() async {
    print('$_logPrefix 🔥 Connecting to Solflare...');
    await _solflareConnector.connectSolflareWallet((pubkey, session) {
      print('$_logPrefix 🔥 ✅ Solflare connection successful!');
      print('$_logPrefix 🔥 Public Key: $pubkey');
      print('$_logPrefix 🔥 Session: ${session.substring(0, 20)}...');
      _updateState(
        state.copyWith(
          isConnected: true,
          publicKey: pubkey,
          walletType: WalletType.solflare,
          session: session,
          accountLabel: 'Solflare',
          isConnecting: false,
          error: null,
        ),
      );
    });
  }

  // Add method to set Android connection with logging
  void setAndroidConnection(String publicKey, AuthorizationResult authResult) {
    print('$_logPrefix 🤖 Setting Android connection');
    print('$_logPrefix 🤖 Public Key: $publicKey');
    print('$_logPrefix 🤖 Account Label: ${authResult.accountLabel}');

    _updateState(
      state.copyWith(
        isConnected: true,
        publicKey: publicKey,
        walletType: null,
        // Android MWA doesn't specify wallet type
        accountLabel: authResult.accountLabel ?? 'Android Wallet',
        isConnecting: false,
        error: null,
      ),
    );
  }

  void disconnect() {
    print('$_logPrefix 🔌 Disconnecting wallet...');
    print('$_logPrefix 🔌 Previous wallet: ${state.walletType}');
    _updateState(const WalletState()); // Reset to initial state
    print('$_logPrefix 🔌 ✅ Wallet disconnected');
  }

  Future<void> sendTransaction(String serializedTransaction) async {
    print('$_logPrefix 📤 Starting transaction...');
    print('$_logPrefix 📤 Wallet: $currentWallet');
    print('$_logPrefix 📤 Transaction length: ${serializedTransaction.length} chars');

    if (!isConnected) {
      print('$_logPrefix 📤 ❌ Wallet not connected');
      throw Exception('Wallet not connected');
    }

    try {
      _updateState(state.copyWith(error: null));

      switch (currentWallet) {
        case WalletType.phantom:
          print('$_logPrefix 📤 👻 Sending Phantom transaction...');
          await _sendPhantomTransaction(serializedTransaction);
          break;
        case WalletType.solflare:
          print('$_logPrefix 📤 🔥 Sending Solflare transaction...');
          await _sendSolflareTransaction(serializedTransaction);
          break;
        default:
          print('$_logPrefix 📤 ❌ No wallet connected');
          throw Exception('No wallet connected');
      }
      print('$_logPrefix 📤 ✅ Transaction sent to wallet');
    } catch (e) {
      print('$_logPrefix 📤 ❌ Transaction failed: $e');
      _updateState(state.copyWith(error: e.toString()));
      rethrow;
    }
  }

  Future<void> _sendPhantomTransaction(String serializedTransaction) async {
    print('$_logPrefix 📤👻 Preparing Phantom deep link...');
    final nonce = _generateNonce();
    print('$_logPrefix 📤👻 Generated nonce: ${nonce.substring(0, 10)}...');

    final Uri phantomUri = Uri.https('phantom.app', '/ul/v1/signAndSendTransaction', {
      'dapp_encryption_public_key': nonce,
      'redirect_link': 'test5wallet://phantom',
      'transaction': serializedTransaction,
      'cluster': 'devnet',
    });

    print('$_logPrefix 📤👻 Deep link URL: $phantomUri');

    if (await canLaunchUrl(phantomUri)) {
      print('$_logPrefix 📤👻 Launching Phantom...');
      await launchUrl(phantomUri, mode: LaunchMode.externalApplication);
      print('$_logPrefix 📤👻 ✅ Phantom launched successfully');
    } else {
      print('$_logPrefix 📤👻 ❌ Cannot launch Phantom URL');
      throw Exception('Cannot launch Phantom');
    }
  }

  Future<void> _sendSolflareTransaction(String serializedTransaction) async {
    if (state.session == null) {
      print('$_logPrefix 📤🔥 ❌ No Solflare session available');
      throw Exception('Solflare session not available');
    }

    print('$_logPrefix 📤🔥 Preparing Solflare deep link...');
    print('$_logPrefix 📤🔥 Session: ${state.session!.substring(0, 10)}...');

    final Uri solflareUri = Uri.https('solflare.com', '/ul/v1/signAndSendTransaction', {
      'session': state.session!,
      'transaction': serializedTransaction,
      'redirect_link': 'test5wallet://solflare',
    });

    print('$_logPrefix 📤🔥 Deep link URL: $solflareUri');

    if (await canLaunchUrl(solflareUri)) {
      print('$_logPrefix 📤🔥 Launching Solflare...');
      await launchUrl(solflareUri, mode: LaunchMode.externalApplication);
      print('$_logPrefix 📤🔥 ✅ Solflare launched successfully');
    } else {
      print('$_logPrefix 📤🔥 ❌ Cannot launch Solflare URL');
      throw Exception('Cannot launch Solflare');
    }
  }

  String _generateNonce() {
    final rand = Random.secure();
    final bytes = Uint8List(32)..setAll(0, List.generate(32, (_) => rand.nextInt(256)));
    final nonce = base58encode(bytes);
    print('$_logPrefix 🎲 Generated nonce: ${nonce.substring(0, 10)}...');
    return nonce;
  }

  @override
  void dispose() {
    print('$_logPrefix 🗑️ Disposing wallet manager...');
    _stateNotifier.dispose();
    super.dispose();
    print('$_logPrefix 🗑️ ✅ Wallet manager disposed');
  }
}
