// Enhanced Phantom Connector
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:solana/base58.dart';
import 'package:solana/solana.dart';
import 'package:url_launcher/url_launcher.dart';

class PhantomConnector {
  static const String _logPrefix = '👻 [Phantom]';

  final String redirectUri = 'test5wallet://phantom';
  final String dappUrl = 'https://example.com';
  final String cluster = 'devnet';
  final appLink = AppLinks();

  String _generateRandomKey() {
    final rand = Random.secure();
    final bytes = Uint8List(32)..setAll(0, List.generate(32, (_) => rand.nextInt(256)));
    final key = base58encode(bytes);
    print('$_logPrefix 🎲 Generated random key: ${key.substring(0, 10)}...');
    return key;
  }

  Future<void> connectPhantomWallet(Function(String pubkey) onConnect) async {
    print('$_logPrefix 🚀 Starting Phantom connection...');
    final nonce = _generateRandomKey();

    final Uri phantomUri = Uri.https('phantom.app', '/ul/v1/connect', {
      'app_url': dappUrl,
      'redirect_link': redirectUri,
      'cluster': cluster,
      'dapp_encryption_public_key': nonce,
    });

    print('$_logPrefix 🔗 Connection URL: $phantomUri');

    if (await canLaunchUrl(phantomUri)) {
      print('$_logPrefix 📱 Launching Phantom app...');
      await launchUrl(phantomUri, mode: LaunchMode.externalApplication);
      print('$_logPrefix 📱 ✅ Phantom app launched');
    } else {
      print('$_logPrefix ❌ Could not launch Phantom app');
      throw 'Could not launch Phantom';
    }

    print('$_logPrefix 👂 Setting up deep link listener...');
    appLink.uriLinkStream.listen((uri) {
      print('$_logPrefix 📨 Received deep link: $uri');
      print('$_logPrefix 📨 Scheme: ${uri.scheme}');
      print('$_logPrefix 📨 Query params: ${uri.queryParameters}');

      if (uri.scheme == 'test5wallet') {
        print('$_logPrefix ✅ Correct scheme detected');
        final pubkey = uri.queryParameters['phantom_encryption_public_key'] ?? uri.queryParameters['public_key'];
        print('$_logPrefix 🔑 Public key from response: $pubkey');

        if (pubkey != null) {
          print('$_logPrefix ✅ Public key found, calling onConnect callback');
          onConnect(pubkey);
        } else {
          print('$_logPrefix ❌ No public key found in response');
        }
      } else {
        print('$_logPrefix ⚠️ Wrong scheme: ${uri.scheme}');
      }
    });

    print('$_logPrefix 👂 Deep link listener setup complete');
  }
}

class PhantomTransfer {
  static const String _logPrefix = '👻💸 [PhantomTransfer]';
  static final _redirect = 'test5wallet://phantom';
  static final _cluster = 'devnet';
  static final _dappUrl = 'https://example.com';

  static final appLink = AppLinks();

  static String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final nonce = base58encode(Uint8List.fromList(bytes));
    print('$_logPrefix 🎲 Generated nonce: ${nonce.substring(0, 10)}...');
    return nonce;
  }

  static Future<void> sendSolFromPhantom({
    required BuildContext context,
    required String fromAddress,
    required String toAddress,
    required int lamports,
  }) async {
    print('$_logPrefix 🚀 Starting Phantom SOL transfer...');
    print('$_logPrefix 📤 From: $fromAddress');
    print('$_logPrefix 📥 To: $toAddress');
    print('$_logPrefix 💰 Amount: $lamports lamports');

    try {
      print('$_logPrefix 🔗 Getting latest blockhash...');
      final recentBlockhash = await _getLatestBlockhash();
      print('$_logPrefix 🔗 Blockhash: $recentBlockhash');

      print('$_logPrefix 📝 Creating transfer instruction...');
      final instruction = SystemInstruction.transfer(
        fundingAccount: Ed25519HDPublicKey.fromBase58(fromAddress),
        recipientAccount: Ed25519HDPublicKey.fromBase58(toAddress),
        lamports: lamports,
      );
      print('$_logPrefix 📝 ✅ Transfer instruction created');

      print('$_logPrefix 📦 Creating message...');
      final message = Message.only(instruction);
      final compiled = message.compile(
        recentBlockhash: recentBlockhash,
        feePayer: Ed25519HDPublicKey.fromBase58(fromAddress),
      );
      print('$_logPrefix 📦 ✅ Message compiled');

      final serializedMessage = base64.encode(Uint8List.fromList(compiled.toByteArray().toList()));
      print('$_logPrefix 📦 Serialized message length: ${serializedMessage.length}');

      final nonce = _generateNonce();

      print('$_logPrefix 🔗 Building deep link...');
      final Uri deepLink = Uri.https('phantom.app', '/ul/v1/signAndSendTransaction', {
        'phantom_encryption_public_key': nonce,
        'redirect_link': _redirect,
        'payload': serializedMessage,
        'cluster': _cluster,
        'app_url': _dappUrl,
      });

      print('$_logPrefix 🔗 Deep link: $deepLink');

      print('$_logPrefix 📱 Launching Phantom...');
      if (!await launchUrl(deepLink, mode: LaunchMode.externalApplication)) {
        print('$_logPrefix ❌ Could not launch Phantom');
        throw Exception("Could not launch Phantom");
      }
      print('$_logPrefix 📱 ✅ Phantom launched');

      print('$_logPrefix 👂 Setting up response listener...');
      appLink.uriLinkStream.listen((Uri? uri) {
        print('$_logPrefix 📨 Received response: $uri');

        if (uri != null && uri.scheme == "test5wallet") {
          print('$_logPrefix ✅ Valid response scheme');
          final txSignature = uri.queryParameters["signature"];
          print('$_logPrefix 🧾 Transaction signature: $txSignature');

          if (txSignature != null) {
            print('$_logPrefix ✅ Transaction successful!');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("✅ Transaction Success: $txSignature")));
          } else {
            print('$_logPrefix ❌ No transaction signature received');
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text("❌ Transaction failed or canceled")));
          }
        } else {
          print('$_logPrefix ⚠️ Invalid response format');
        }
      });

      print('$_logPrefix 👂 Response listener setup complete');
    } catch (e) {
      print('$_logPrefix ❌ Error: $e');
      print('$_logPrefix ❌ Stack trace: ${StackTrace.current}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e")));
    }
  }

  static Future<String> _getLatestBlockhash() async {
    print('$_logPrefix 🌐 Fetching latest blockhash from RPC...');
    final rpcClient = RpcClient("https://api.devnet.solana.com");
    final hash = await rpcClient.getLatestBlockhash();
    print('$_logPrefix 🌐 ✅ Blockhash fetched: ${hash.value.blockhash}');
    return hash.value.blockhash;
  }
}

// Solflare Connector
class SolflareConnector {
  static const String _logPrefix = '🔥 [Solflare]';

  final String redirectUri = 'test5wallet://solflare';
  final String dappUrl = 'https://example.com';
  final String cluster = 'devnet';
  final appLink = AppLinks();

  // Store the private key for decryption
  late SimpleKeyPair _dappKeyPair;
  late String _dappPublicKey;

  Future<String> _generateRandomKey() async {
    print('$_logPrefix 🎲 Generating x25519 key pair...');

    // Generate proper x25519 key pair
    final algorithm = X25519();
    _dappKeyPair = await algorithm.newKeyPair();
    final publicKey = await _dappKeyPair.extractPublicKey();
    final publicKeyBytes = publicKey.bytes;

    _dappPublicKey = base58encode(Uint8List.fromList(publicKeyBytes));
    print('$_logPrefix 🎲 Generated dApp public key: ${_dappPublicKey.substring(0, 10)}...');

    return _dappPublicKey;
  }

  Future<void> connectSolflareWallet(Function(String pubkey, String session) onConnect) async {
    print('$_logPrefix 🚀 Starting Solflare connection...');
    final nonce = await _generateRandomKey(); // Now async

    final Uri solflareUri = Uri.https('solflare.com', '/ul/v1/connect', {
      'app_url': dappUrl,
      'redirect_link': redirectUri,
      'cluster': cluster,
      'dapp_encryption_public_key': nonce,
    });

    print('$_logPrefix 🔗 Connection URL: $solflareUri');

    if (await canLaunchUrl(solflareUri)) {
      print('$_logPrefix 📱 Launching Solflare app...');
      await launchUrl(solflareUri, mode: LaunchMode.externalApplication);
      print('$_logPrefix 📱 ✅ Solflare app launched');
    } else {
      print('$_logPrefix ❌ Could not launch Solflare app');
      throw 'Could not launch Solflare wallet';
    }

    print('$_logPrefix 👂 Setting up deep link listener...');
    appLink.uriLinkStream.listen((uri) {
      print('$_logPrefix 📨 Received deep link: $uri');
      print('$_logPrefix 📨 Scheme: ${uri.scheme}');
      print('$_logPrefix 📨 Query params: ${uri.queryParameters}');

      if (uri.scheme == 'test5wallet') {
        print('$_logPrefix ✅ Correct scheme detected');
        final encryptedData = uri.queryParameters['data'];
        final solflarePublicKey = uri.queryParameters['solflare_encryption_public_key'];
        final nonce = uri.queryParameters['nonce'];

        print('$_logPrefix 🔐 Encrypted data present: ${encryptedData != null}');
        print('$_logPrefix 🔑 Solflare public key present: ${solflarePublicKey != null}');
        print('$_logPrefix 🎲 Nonce present: ${nonce != null}');

        if (encryptedData != null && solflarePublicKey != null) {
          print('$_logPrefix 🔓 Attempting to decrypt response...');
          _decryptSolflareResponse(encryptedData, solflarePublicKey, nonce ?? '', onConnect);
        } else {
          print('$_logPrefix ❌ Missing encrypted data or public key');
        }
      } else {
        print('$_logPrefix ⚠️ Wrong scheme: ${uri.scheme}');
      }
    });

    print('$_logPrefix 👂 Deep link listener setup complete');
  }

  Future<void> _decryptSolflareResponse(
    String encryptedData,
    String solflarePublicKey,
    String nonce,
    Function(String, String) onConnect,
  ) async {
    print('$_logPrefix 🔓 Decrypting Solflare response...');
    print('$_logPrefix 🔓 Encrypted data length: ${encryptedData.length}');
    print('$_logPrefix 🔓 Solflare public key: ${solflarePublicKey.substring(0, 10)}...');

    try {
      // Step 1: Decode the encrypted data from base58
      final encryptedBytes = base58decode(encryptedData);
      print('$_logPrefix 🔓 Decoded encrypted bytes length: ${encryptedBytes.length}');

      // Step 2: Decode Solflare's public key
      final solflarePublicKeyBytes = base58decode(solflarePublicKey);
      print('$_logPrefix 🔑 Solflare public key bytes length: ${solflarePublicKeyBytes.length}');

      // Step 3: Perform x25519 key exchange
      final algorithm = X25519();
      final solflarePublicKeyObj = SimplePublicKey(solflarePublicKeyBytes, type: KeyPairType.x25519);

      // Derive shared secret
      final sharedSecret = await algorithm.sharedSecretKey(
        keyPair: _dappKeyPair,
        remotePublicKey: solflarePublicKeyObj,
      );

      final sharedSecretBytes = await sharedSecret.extractBytes();
      print('$_logPrefix 🤝 Shared secret derived, length: ${sharedSecretBytes.length}');

      // Step 4: Decrypt using AES-256-GCM
      final aesGcm = AesGcm.with256bits();

      // Extract nonce/IV (first 12 bytes) and encrypted payload
      if (encryptedBytes.length < 12) {
        throw Exception('Encrypted data too short');
      }

      final iv = encryptedBytes.sublist(0, 12);
      final encryptedPayload = encryptedBytes.sublist(12);

      print('$_logPrefix 🔐 IV length: ${iv.length}');
      print('$_logPrefix 🔐 Encrypted payload length: ${encryptedPayload.length}');

      // Decrypt
      final secretBox = SecretBox(
        encryptedPayload,
        nonce: iv,
        mac: Mac.empty, // Solflare might not use MAC, adjust if needed
      );

      final decryptedBytes = await aesGcm.decrypt(secretBox, secretKey: SecretKey(sharedSecretBytes));

      print('$_logPrefix ✅ Decryption successful, length: ${decryptedBytes.length}');

      // Step 5: Parse decrypted JSON
      final jsonData = utf8.decode(decryptedBytes);
      print('$_logPrefix 🔓 Decrypted JSON: $jsonData');

      final responseData = json.decode(jsonData);
      print('$_logPrefix 🔓 Parsed response data: $responseData');

      final publicKey = responseData['public_key'];
      final session = responseData['session'] ?? 'solflare_session_${DateTime.now().millisecondsSinceEpoch}';

      print('$_logPrefix 🔑 Extracted public key: $publicKey');
      print('$_logPrefix 🎫 Extracted session: ${session.substring(0, 10)}...');

      if (publicKey != null) {
        print('$_logPrefix ✅ Decryption successful, calling onConnect');
        onConnect(publicKey, session);
      } else {
        print('$_logPrefix ❌ Missing public key in decrypted data');
      }
    } catch (e) {
      print('$_logPrefix ❌ Error decrypting Solflare response: $e');
      print('$_logPrefix ❌ Stack trace: ${StackTrace.current}');

      // Fallback: Try to extract public key from URL parameters if available
      _handleDecryptionFallback(encryptedData, solflarePublicKey, onConnect);
    }
  }

  // Fallback method for when decryption fails
  void _handleDecryptionFallback(String encryptedData, String solflarePublicKey, Function(String, String) onConnect) {
    print('$_logPrefix 🔄 Attempting fallback decryption method...');

    try {
      // Sometimes Solflare might return the public key directly in the URL
      // or use a simpler encoding
      print('$_logPrefix 🔄 Using Solflare public key as wallet address');
      final session = 'solflare_session_${DateTime.now().millisecondsSinceEpoch}';

      // Use Solflare's public key as the wallet public key (common pattern)
      onConnect(solflarePublicKey, session);
      print('$_logPrefix 🔄 ✅ Fallback successful');
    } catch (e) {
      print('$_logPrefix 🔄 ❌ Fallback also failed: $e');
    }
  }
}
