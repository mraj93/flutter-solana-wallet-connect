// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:solana/dto.dart' hide TokenBalance;
import 'package:solana/solana.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';

import 'ios_wallet_helper.dart';
import 'wallet_model.dart';

class UnifiedWalletManager extends ChangeNotifier {
  UnifiedWalletManager({required SolanaClient solanaClient}) : _solanaClient = solanaClient;

  static const _log = '🔗 [WalletManager]';

  final PhantomConnector _phantom = PhantomConnector();
  final SolflareConnector _solflare = SolflareConnector();
  final SolanaClient _solanaClient;

  final ValueNotifier<WalletState> _state = ValueNotifier<WalletState>( // ✅ Fixed: Added generic type
    const WalletState(),
  );

  // Expose immutable listenable
  ValueListenable<WalletState> get stateNotifier => _state; // ✅ Fixed: Added generic type

  WalletState get _s => _state.value;

  // ---------- PUBLIC API ----------

  Future<void> connectWallet(WalletType wt) async {
    if (_s.isConnecting) return;
    _set(_s.copyWith(isConnecting: true, error: null));

    try {
      if (wt == WalletType.phantom) {
        print('$_log 👻 Connecting to Phantom...');
        await _phantom.connect((pk) => _onConnected(pk, wt)); // ✅ Fixed: Proper callback
      } else {
        print('$_log 🔥 Connecting to Solflare...');
        await _solflare.connect((pk, sess) => _onConnected(pk, wt, sess));
      }
    } catch (e, stackTrace) {
      print('$_log ❌ Connection error: $e');
      print('$_log ❌ Connection stackTrace : $stackTrace');
      _set(_s.copyWith(isConnecting: false, error: '$e'));
    }
  }

  void disconnect() {
    print('$_log 🔌 disconnect');
    _phantom.disconnect();
    _set(const WalletState());
  }

  Future<void> fetchAllBalances() async {
    print('$_log 💰 📊 Starting fetchAllBalances...');
    print('$_log 💰 📊 Current state - Connected: ${_s.isConnected}, Loading: ${_s.isLoadingBalances}');
    print('$_log 💰 📊 Public Key: ${_s.publicKey}');

    if (!_s.isConnected || _s.isLoadingBalances) {
      print('$_log 💰 📊 ❌ Cannot fetch balances - wallet not connected or already loading');
      return;
    }

    _set(_s.copyWith(isLoadingBalances: true));
    print('$_log 💰 📊 ✅ Set loading state to true');

    try {
      print('$_log 💰 📊 🚀 Starting parallel balance fetch...');
      final sol = await _solBalance();
      print('$_log 💰 📊 ✅ SOL balance fetched: $sol');

      final spl = await _splTokens();
      print('$_log 💰 📊 ✅ SPL tokens fetched: ${spl.length} tokens');

      _set(_s.copyWith(
        solBalance: sol,
        tokenBalances: spl,
        isLoadingBalances: false,
      ));
      print('$_log 💰 📊 ✅ Balance fetch completed successfully');
      print('$_log 💰 📊 📈 Final state - SOL: $sol, Tokens: ${spl.length}');
    } catch (e) {
      print('$_log 💰 📊 ❌ Balance fetch error: $e');
      print('$_log 💰 📊 ❌ Stack trace: ${StackTrace.current}');
      _set(_s.copyWith(
        isLoadingBalances: false,
        error: 'Balance error: $e',
      ));
    }
  }

  // ---------- INTERNAL ----------

  void _onConnected(String pub, WalletType wt, [String? sess]) {
    print('$_log ✅ connected $wt');
    _set(
      _s.copyWith(
        isConnected: true,
        isConnecting: false,
        publicKey: pub,
        walletType: wt,
        session: sess,
        accountLabel: wt.name,
      ),
    );
  }

  Future<double> _solBalance() async {
    print('$_log 💰 SOL 🚀 Starting SOL balance fetch...');
    print('$_log 💰 SOL 🔑 Public Key: ${_s.publicKey}');

    try {
      final bal = await _solanaClient.rpcClient.getBalance(
        _s.publicKey!,
        commitment: Commitment.confirmed,
      );
      final solBalance = bal.value / lamportsPerSol;
      print('$_log 💰 SOL ✅ Raw balance: ${bal.value} lamports');
      print('$_log 💰 SOL ✅ Converted balance: $solBalance SOL');
      return solBalance;
    } catch (e) {
      print('$_log 💰 SOL ❌ Error fetching SOL balance: $e');
      print('$_log 💰 SOL ❌ Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  Future<List<TokenBalance>> _splTokens() async {
    print('$_log 🪙 SPL 🚀 Starting SPL token fetch...');
    print('$_log 🪙 SPL 🔑 Wallet Public Key: ${_s.publicKey}');
    print('$_log 🪙 SPL 🏦 Token Program ID: ${TokenProgram.programId}');

    try {
      print('$_log 🪙 SPL 📡 Calling getTokenAccountsByOwner...');
      final stopwatch = Stopwatch()..start();

      final accs = await _solanaClient.rpcClient.getTokenAccountsByOwner(
        _s.publicKey!,
        TokenAccountsFilter.byProgramId(TokenProgram.programId),
        encoding: Encoding.jsonParsed,
        commitment: Commitment.confirmed,
      );

      stopwatch.stop();
      print('$_log 🪙 SPL ✅ RPC call completed in ${stopwatch.elapsedMilliseconds}ms');
      print('$_log 🪙 SPL 📊 Found ${accs.value.length} token accounts');

      if (accs.value.isEmpty) {
        print('$_log 🪙 SPL ⚠️ No token accounts found for this wallet');
        return [];
      }

      final out = <TokenBalance>[];
      int processedCount = 0;
      int validTokenCount = 0;
      int zeroBalanceCount = 0;
      int errorCount = 0;

      for (int i = 0; i < accs.value.length; i++) {
        final a = accs.value[i];
        processedCount++;

        print('$_log 🪙 SPL 🔍 Processing account ${i + 1}/${accs.value.length}');
        print('$_log 🪙 SPL 🔍 Account Address: ${a.pubkey}');
        print('$_log 🪙 SPL 🔍 Account Owner: ${a.account.owner}');
        print('$_log 🪙 SPL 🔍 Account Data Type: ${a.account.data.runtimeType}');

        try {
          // Check if data is ParsedAccountData
          if (a.account.data is! ParsedAccountData) {
            print('$_log 🪙 SPL ❌ Account $i: Data is not ParsedAccountData, got: ${a.account.data.runtimeType}');
            errorCount++;
            continue;
          }

          final parsedAccountData = a.account.data as ParsedAccountData;
          final dataJson = parsedAccountData.toJson();
          print('$_log 🪙 SPL 🔍 Account $i: Root JSON keys: ${dataJson.keys.toList()}');

          // ✅ FIXED: Look for 'parsed' first, not 'info' directly
          if (!dataJson.containsKey('parsed')) {
            print('$_log 🪙 SPL ❌ Account $i: No "parsed" field in data');
            print('$_log 🪙 SPL 🔍 Account $i: Available root fields: ${dataJson.keys.toList()}');
            errorCount++;
            continue;
          }

          // ✅ FIXED: Navigate to parsed first
          final parsedData = dataJson['parsed'] as Map;
          print('$_log 🪙 SPL 🔍 Account $i: Parsed keys: ${parsedData.keys.toList()}');

          // ✅ FIXED: Now look for 'info' inside 'parsed'
          if (!parsedData.containsKey('info')) {
            print('$_log 🪙 SPL ❌ Account $i: No "info" field in parsed data');
            print('$_log 🪙 SPL 🔍 Account $i: Available parsed fields: ${parsedData.keys.toList()}');
            errorCount++;
            continue;
          }

          // ✅ FIXED: Get info from parsed data
          final info = parsedData['info'] as Map;
          print('$_log 🪙 SPL 🔍 Account $i: Info keys: ${info.keys.toList()}');

          if (!info.containsKey('tokenAmount') || !info.containsKey('mint')) {
            print('$_log 🪙 SPL ❌ Account $i: Missing tokenAmount or mint field');
            print('$_log 🪙 SPL 🔍 Account $i: Available info fields: ${info.keys.toList()}');
            errorCount++;
            continue;
          }

          // ✅ FIXED: Get data from info (not parsed)
          final amt = info['tokenAmount'] as Map;
          final mint = info['mint'] as String;

          print('$_log 🪙 SPL 🔍 Account $i: Mint: $mint');
          print('$_log 🪙 SPL 🔍 Account $i: TokenAmount keys: ${amt.keys.toList()}');
          print('$_log 🪙 SPL 🔍 Account $i: Raw amount: ${amt['amount']}');
          print('$_log 🪙 SPL 🔍 Account $i: Decimals: ${amt['decimals']}');
          print('$_log 🪙 SPL 🔍 Account $i: UI amount: ${amt['uiAmount']}');

          final rawAmount = amt['amount'].toString(); // Handle both int and string
          final decimals = amt['decimals'] as int;
          final bal = double.parse(rawAmount) / pow(10, decimals);

          print('$_log 🪙 SPL 🔍 Account $i: Calculated balance: $bal');

          if (bal <= 0) { // ✅ Changed from == 0 to <= 0 for safety
            print('$_log 🪙 SPL ⚪ Account $i: Zero or negative balance ($bal), skipping');
            zeroBalanceCount++;
            continue;
          }

          validTokenCount++;
          final token = TokenBalance(
            mintAddress: mint,
            tokenAddress: a.pubkey,
            balance: bal,
            decimals: decimals,
            symbol: 'SPL-${mint.substring(0, 4)}…',
          );

          out.add(token);
          print('$_log 🪙 SPL ✅ Account $i: Added token - Mint: $mint, Balance: $bal');

        } catch (e) {
          errorCount++;
          print('$_log 🪙 SPL ❌ Account $i: Error parsing - $e');
          print('$_log 🪙 SPL ❌ Account $i: Stack trace: ${StackTrace.current}');
          continue;
        }
      }

      print('$_log 🪙 SPL 📊 === FINAL SPL SUMMARY ===');
      print('$_log 🪙 SPL 📊 Total accounts found: ${accs.value.length}');
      print('$_log 🪙 SPL 📊 Accounts processed: $processedCount');
      print('$_log 🪙 SPL 📊 Valid tokens (balance > 0): $validTokenCount');
      print('$_log 🪙 SPL 📊 Zero balance tokens: $zeroBalanceCount');
      print('$_log 🪙 SPL 📊 Parse errors: $errorCount');
      print('$_log 🪙 SPL 📊 Tokens returned: ${out.length}');

      if (out.isNotEmpty) {
        print('$_log 🪙 SPL 📊 === TOKEN DETAILS ===');
        for (int i = 0; i < out.length; i++) {
          final token = out[i];
          print('$_log 🪙 SPL 📊 Token ${i + 1}: ${token.symbol} - ${token.balance} (${token.mintAddress})');
        }
      } else {
        print('$_log 🪙 SPL ⚠️ No tokens with balance > 0 found!');
        if (accs.value.isNotEmpty) {
          print('$_log 🪙 SPL ⚠️ This could mean:');
          print('$_log 🪙 SPL ⚠️ 1. All tokens have zero balance');
          print('$_log 🪙 SPL ⚠️ 2. Data parsing failed');
          print('$_log 🪙 SPL ⚠️ 3. Wrong network (devnet vs mainnet)');
          print('$_log 🪙 SPL ⚠️ 4. Tokens are on a different program ID');
        }
      }

      return out;

    } catch (e) {
      print('$_log 🪙 SPL ❌ Critical error in _splTokens: $e');
      print('$_log 🪙 SPL ❌ Stack trace: ${StackTrace.current}');
      return [];
    }
  }


  void _set(WalletState s) {
    print('$_log 📊 State update: Connected=${s.isConnected}, Loading=${s.isLoadingBalances}, TokenCount=${s.tokenBalances.length}');
    _state.value = s;
    notifyListeners();
  }

  void setAndroidConnection(String publicKey, AuthorizationResult authResult) {
    print('$_log 🤖 Setting Android connection');
    print('$_log 🤖 Public Key: $publicKey');
    print('$_log 🤖 Account Label: ${authResult.accountLabel}');

    _set(_s.copyWith(
      isConnected: true,
      publicKey: publicKey,
      walletType: null, // Android MWA doesn't specify wallet type
      accountLabel: authResult.accountLabel ?? 'Android Wallet',
      isConnecting: false,
      error: null,
    ));
  }

  @override
  void dispose() {
    print('$_log 🗑️ Disposing UnifiedWalletManager...');
    _phantom.disconnect();
    _state.dispose();
    super.dispose();
    print('$_log 🗑️ ✅ UnifiedWalletManager disposed');
  }
}
