class WalletState {
  final bool isConnected;
  final String? publicKey;
  final WalletType? walletType;
  final String? session;
  final String? accountLabel;
  final bool isConnecting;
  final String? error;

  const WalletState({
    this.isConnected = false,
    this.publicKey,
    this.walletType,
    this.session,
    this.accountLabel,
    this.isConnecting = false,
    this.error,
  });

  WalletState copyWith({
    bool? isConnected,
    String? publicKey,
    WalletType? walletType,
    String? session,
    String? accountLabel,
    bool? isConnecting,
    String? error,
  }) {
    return WalletState(
      isConnected: isConnected ?? this.isConnected,
      publicKey: publicKey ?? this.publicKey,
      walletType: walletType ?? this.walletType,
      session: session ?? this.session,
      accountLabel: accountLabel ?? this.accountLabel,
      isConnecting: isConnecting ?? this.isConnecting,
      error: error ?? this.error,
    );
  }
}

enum WalletType { phantom, solflare }
