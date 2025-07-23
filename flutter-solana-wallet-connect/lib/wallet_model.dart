import 'package:meta/meta.dart';

@immutable
class WalletState {
  const WalletState({
    this.isConnected = false,
    this.publicKey,
    this.walletType,
    this.session,
    this.accountLabel,
    this.isConnecting = false,
    this.error,
    this.isLoadingBalances = false,
    this.solBalance,
    this.tokenBalances = const <TokenBalance>[], // ✅ Fixed: Added generic type
  });

  final bool isConnected;
  final String? publicKey;
  final WalletType? walletType;
  final String? session;
  final String? accountLabel;
  final bool isConnecting;
  final String? error;
  final bool isLoadingBalances;
  final double? solBalance;
  final List<TokenBalance> tokenBalances; // ✅ Fixed: Added generic type

  WalletState copyWith({
    bool? isConnected,
    String? publicKey,
    WalletType? walletType,
    String? session,
    String? accountLabel,
    bool? isConnecting,
    String? error,
    bool? isLoadingBalances,
    double? solBalance,
    List<TokenBalance>? tokenBalances, // ✅ Fixed: Added generic type
  }) {
    return WalletState(
      isConnected: isConnected ?? this.isConnected,
      publicKey: publicKey ?? this.publicKey,
      walletType: walletType ?? this.walletType,
      session: session ?? this.session,
      accountLabel: accountLabel ?? this.accountLabel,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
      isLoadingBalances: isLoadingBalances ?? this.isLoadingBalances,
      solBalance: solBalance ?? this.solBalance,
      tokenBalances: tokenBalances ?? this.tokenBalances,
    );
  }
}

@immutable
class TokenBalance {
  const TokenBalance({
    required this.mintAddress,
    required this.tokenAddress,
    required this.balance,
    required this.decimals,
    this.name,
    this.symbol,
    this.logoURI,
  });

  final String mintAddress;
  final String tokenAddress;
  final double balance;
  final int decimals;
  final String? name;
  final String? symbol;
  final String? logoURI;

  factory TokenBalance.fromJson(Map<String, dynamic> json) { // ✅ Fixed: Added generic types
    return TokenBalance(
      mintAddress: json['mintAddress'] as String? ?? '',
      tokenAddress: json['tokenAddress'] as String? ?? '',
      balance: (json['balance'] as num? ?? 0).toDouble(),
      decimals: json['decimals'] as int? ?? 0,
      name: json['name'] as String?,
      symbol: json['symbol'] as String?,
      logoURI: json['logoURI'] as String?,
    );
  }
}

enum WalletType { phantom, solflare }

class WalletInfo {
  final String name;
  final String iconUrl;

  WalletInfo({
    required this.name,
    required this.iconUrl,
  });
}
