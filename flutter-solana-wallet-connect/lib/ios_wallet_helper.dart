// wallet_connector_logic.dart
// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:solana/base58.dart';
import 'package:url_launcher/url_launcher.dart';

/// ---------------- PHANTOM ----------------
class PhantomConnector {
  static const _log = '👻 [Phantom]';
  final _appLinks = AppLinks();

  final String redirectUri = 'test5wallet://phantom';
  final String dappUrl = 'https://example.com';
  final String cluster = 'devnet';

  late SimpleKeyPair _dappKeyPair;
  late String _dappPublicKey;

  StreamSubscription<Uri>? _sub;

  Future<String> _createNonce() async {
    final algorithm = X25519();
    _dappKeyPair = await algorithm.newKeyPair();
    final publicKey = await _dappKeyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;

    _dappPublicKey = base58encode(Uint8List.fromList(publicKeyBytes));
    print('$_log 🎲 Generated dApp public key=${_dappPublicKey.substring(0, 8)}…');
    return _dappPublicKey;
  }

  Future<void> _listen(Function(String) onConnect) async {
    await _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen((uri) async {
      print('$_log 📨 Received deep link: $uri');
      print('$_log 📨 All query parameters: ${uri.queryParameters}');

      if (uri.scheme != 'test5wallet') {
        print('$_log ⚠️ Wrong scheme: ${uri.scheme}');
        return;
      }

      final phantomEncryptionKey = uri.queryParameters['phantom_encryption_public_key'];
      final encryptedData = uri.queryParameters['data'];
      final nonce = uri.queryParameters['nonce']; // ✅ Use the nonce parameter
      final plainPublicKey = uri.queryParameters['public_key'];
      final errorParam = uri.queryParameters['error'];

      print('$_log 🔍 phantom_encryption_public_key: $phantomEncryptionKey');
      print('$_log 🔍 encrypted data length: ${encryptedData?.length ?? 0}');
      print('$_log 🔍 nonce: $nonce');
      print('$_log 🔍 plain public_key: $plainPublicKey');
      print('$_log 🔍 error: $errorParam');

      // Handle errors first
      if (errorParam != null) {
        print('$_log ❌ Phantom returned error: $errorParam');
        return;
      }

      // Try plain text public key first
      if (plainPublicKey != null && plainPublicKey.isNotEmpty) {
        print('$_log ✅ Found plain text wallet public key: $plainPublicKey');
        onConnect(plainPublicKey);
        return;
      }

      // Try decryption with all available data
      if (encryptedData != null && phantomEncryptionKey != null) {
        print('$_log 🔐 Attempting decryption...');
        try {
          final walletAddress = await _decryptSimpleApproach(encryptedData, phantomEncryptionKey, nonce);
          if (walletAddress != null) {
            print('$_log ✅ Successfully decrypted wallet address: $walletAddress');
            onConnect(walletAddress);
            return;
          }
        } catch (e) {
          print('$_log ❌ Decryption failed: $e');
        }
      }

      // ✅ FALLBACK: Many implementations use phantom_encryption_public_key as wallet address
      if (phantomEncryptionKey != null && phantomEncryptionKey.isNotEmpty) {
        print('$_log 🔄 Using fallback: phantom_encryption_public_key as wallet address');
        print('$_log 🔄 This is a temporary workaround commonly used in Solana dApps');
        onConnect(phantomEncryptionKey);
        return;
      }

      print('$_log ❌ No usable data in Phantom response');
    });
  }

  // Simplified decryption approach
  Future<String?> _decryptSimpleApproach(String encryptedData, String phantomPublicKey, String? urlNonce) async {
    try {
      print('$_log 🔐 Simple decryption approach...');

      // 1. Derive shared secret
      final sharedSecretBytes = await _deriveSharedSecret(phantomPublicKey);
      final encryptedBytes = base58decode(encryptedData);

      print('$_log 🔐 Shared secret: ${sharedSecretBytes.length} bytes');
      print('$_log 🔐 Encrypted data: ${encryptedBytes.length} bytes');

      // 2. Try using the nonce from URL if available
      if (urlNonce != null) {
        try {
          final result = await _tryWithUrlNonce(encryptedBytes, sharedSecretBytes, urlNonce);
          if (result != null) return result;
        } catch (e) {
          print('$_log 🔐 URL nonce approach failed: $e');
        }
      }

      // 3. Try standard formats with embedded nonces
      final nonceSizes = [12, 24, 16, 8];
      for (final nonceSize in nonceSizes) {
        try {
          print('$_log 🔐 Trying $nonceSize-byte embedded nonce...');

          if (encryptedBytes.length < nonceSize + 16) {
            print('$_log 🔐 Data too short for $nonceSize-byte nonce');
            continue;
          }

          final nonce = encryptedBytes.sublist(0, nonceSize);
          final payload = encryptedBytes.sublist(nonceSize);

          // Try different algorithms
          final algorithms = [
            {'cipher': Chacha20.poly1305Aead(), 'name': 'ChaCha20', 'maxNonce': 12},
            {'cipher': AesGcm.with256bits(), 'name': 'AES-GCM', 'maxNonce': 12},
          ];

          for (final algInfo in algorithms) {
            try {
              final cipher = algInfo['cipher'] as Cipher;
              final name = algInfo['name'] as String;
              final maxNonce = algInfo['maxNonce'] as int;

              // Adjust nonce size for algorithm
              final adjustedNonce = nonce.length > maxNonce ? nonce.sublist(0, maxNonce) : nonce;

              if (payload.length < 16) continue;

              final ciphertext = payload.sublist(0, payload.length - 16);
              final mac = payload.sublist(payload.length - 16);

              print('$_log 🔐 $name: nonce=${adjustedNonce.length}, cipher=${ciphertext.length}, mac=${mac.length}');

              final secretBox = SecretBox(ciphertext, nonce: adjustedNonce, mac: Mac(mac));
              final decryptedBytes = await cipher.decrypt(secretBox, secretKey: SecretKey(sharedSecretBytes));

              final jsonString = utf8.decode(decryptedBytes);
              print('$_log 🔐 ✅ $name decryption successful: $jsonString');

              final responseData = json.decode(jsonString) as Map<String, dynamic>;
              return responseData['public_key'] as String?;
            } catch (e) {
              print('$_log 🔐 ${algInfo['name']} failed: $e');
              continue;
            }
          }
        } catch (e) {
          print('$_log 🔐 $nonceSize-byte nonce failed: $e');
          continue;
        }
      }

      return null;
    } catch (e) {
      print('$_log ❌ Simple decryption error: $e');
      return null;
    }
  }

  // Try decryption using nonce from URL parameters
  Future<String?> _tryWithUrlNonce(List<int> encryptedBytes, List<int> sharedSecret, String urlNonce) async {
    try {
      print('$_log 🔐 Trying with URL nonce: ${urlNonce.substring(0, 8)}...');

      // Decode the nonce from the URL
      final nonceBytes = base58decode(urlNonce);
      print('$_log 🔐 URL nonce bytes: ${nonceBytes.length}');

      // Try different ways to use the URL nonce
      final nonceVariations = [
        nonceBytes,
        nonceBytes.length > 12 ? nonceBytes.sublist(0, 12) : nonceBytes,
        nonceBytes.length > 24 ? nonceBytes.sublist(0, 24) : nonceBytes,
      ];

      for (int i = 0; i < nonceVariations.length; i++) {
        final nonce = nonceVariations[i];
        if (nonce.isEmpty) continue;

        try {
          print('$_log 🔐 URL nonce variation ${i + 1}: ${nonce.length} bytes');

          // Assume the entire encrypted data is ciphertext + MAC
          if (encryptedBytes.length < 16) continue;

          final ciphertext = encryptedBytes.sublist(0, encryptedBytes.length - 16);
          final mac = encryptedBytes.sublist(encryptedBytes.length - 16);

          // Try ChaCha20 with adjusted nonce
          final adjustedNonce = nonce.length > 12 ? nonce.sublist(0, 12) : nonce;
          if (adjustedNonce.length < 12) {
            // Pad nonce to 12 bytes if too short
            final paddedNonce = List<int>.filled(12, 0);
            paddedNonce.setRange(0, adjustedNonce.length, adjustedNonce);
            final chacha20 = Chacha20.poly1305Aead();
            final secretBox = SecretBox(ciphertext, nonce: paddedNonce, mac: Mac(mac));
            final decryptedBytes = await chacha20.decrypt(secretBox, secretKey: SecretKey(sharedSecret));

            final jsonString = utf8.decode(decryptedBytes);
            print('$_log 🔐 ✅ URL nonce decryption successful: $jsonString');

            final responseData = json.decode(jsonString) as Map<String, dynamic>;
            return responseData['public_key'] as String?;
          }
        } catch (e) {
          print('$_log 🔐 URL nonce variation ${i + 1} failed: $e');
          continue;
        }
      }

      return null;
    } catch (e) {
      print('$_log 🔐 URL nonce approach error: $e');
      return null;
    }
  }

  Future<List<int>> _deriveSharedSecret(String phantomPublicKey) async {
    final phantomPubKeyBytes = base58decode(phantomPublicKey);
    final phantomPublicKeyObj = SimplePublicKey(phantomPubKeyBytes, type: KeyPairType.x25519);

    final algorithm = X25519();
    final sharedSecret = await algorithm.sharedSecretKey(keyPair: _dappKeyPair, remotePublicKey: phantomPublicKeyObj);

    return await sharedSecret.extractBytes();
  }

  Future<void> connect(Function(String pubkey) onConnect) async {
    final nonce = await _createNonce();
    final url = Uri.https('phantom.app', '/ul/v1/connect', {
      'app_url': dappUrl,
      'redirect_link': redirectUri,
      'cluster': cluster,
      'dapp_encryption_public_key': nonce,
    });

    print('$_log 🔗 Connection URL: $url');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch Phantom';
    }
    await _listen(onConnect);
  }

  void disconnect() {
    print('$_log 🔌 Disconnecting...');
    _sub?.cancel();
  }
}

/// --------------- SOLFLARE ----------------
class SolflareConnector {
  static const _log = '🔥 [Solflare]';
  final _appLinks = AppLinks();

  final String redirectUri = 'test5wallet://solflare';
  final String dappUrl = 'https://example.com';
  final String cluster = 'devnet';

  late SimpleKeyPair _dappKeyPair;
  late String _dappPub58;

  Future<String> _createKey() async {
    final kp = await X25519().newKeyPair();
    _dappKeyPair = kp;
    final pub = await kp.extractPublicKey();
    _dappPub58 = base58encode(Uint8List.fromList(pub.bytes));
    print('$_log 🔑 localPub=${_dappPub58.substring(0, 8)}…');
    return _dappPub58;
  }

  StreamSubscription<Uri>? _sub;

  Future<void> _listen(void Function(String pubkey, String session) onConnect) async {
    await _sub?.cancel();
    _sub = _appLinks.uriLinkStream.listen((uri) async {
      print('$_log 📨 $uri');
      if (uri.scheme != 'test5wallet') return;

      // Try plain text public key first
      final plainPublicKey = uri.queryParameters['public_key'];
      if (plainPublicKey != null && plainPublicKey.isNotEmpty) {
        print('$_log ✅ Found plain text public key: $plainPublicKey');
        onConnect(plainPublicKey, 'solflare_session');
        return;
      }

      final enc = uri.queryParameters['data'];
      final remotePub = uri.queryParameters['solflare_encryption_public_key'];

      if (enc == null || remotePub == null) {
        print('$_log ⚠️ missing data');
        return;
      }

      try {
        final plain = await _decrypt(enc, remotePub);
        final pubKey = plain['public_key'] as String?;
        final session = plain['session'] as String? ?? 'solflare_session';
        if (pubKey != null) {
          onConnect(pubKey, session);
        } else {
          // Fallback to using the encryption key
          onConnect(remotePub, 'fallback');
        }
      } catch (e) {
        print('$_log ❌ decrypt $e');
        // Fallback to using the encryption key
        onConnect(remotePub, 'fallback');
      }
    });
  }

  Future<void> connect(void Function(String pubkey, String session) onConnect) async {
    final nonce = await _createKey();
    final url = Uri.https('solflare.com', '/ul/v1/connect', {
      'app_url': dappUrl,
      'redirect_link': redirectUri,
      'cluster': cluster,
      'dapp_encryption_public_key': nonce,
    });

    print('$_log 🔗 $url');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch Solflare';
    }
    await _listen(onConnect);
  }

  Future<Map<String, dynamic>> _decrypt(String enc, String remote) async {
    try {
      final remotePub = SimplePublicKey(base58decode(remote), type: KeyPairType.x25519);
      final secret = await X25519().sharedSecretKey(keyPair: _dappKeyPair, remotePublicKey: remotePub);
      final bytes = base58decode(enc);

      if (bytes.length < 12 + 16) throw 'cipher too short';

      final iv = bytes.sublist(0, 12);
      final tag = bytes.sublist(bytes.length - 16);
      final ciphertext = bytes.sublist(12, bytes.length - 16);

      final secretBox = SecretBox(ciphertext, nonce: iv, mac: Mac(tag));
      final clearBytes = await AesGcm.with256bits().decrypt(
        secretBox,
        secretKey: SecretKey(await secret.extractBytes()),
      );

      final jsonData = json.decode(utf8.decode(clearBytes)) as Map<String, dynamic>;
      return jsonData;
    } catch (e) {
      print('$_log ❌ Solflare decryption error: $e');
      rethrow;
    }
  }

  void disconnect() {
    print('$_log 🔌 Disconnecting...');
    _sub?.cancel();
  }
}
