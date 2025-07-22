import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connect Wallet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
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

  late LocalAssociationScenario scenario;
  late MobileWalletAdapterClient mwaClient;
  AuthorizationResult? authResult;
  late SolanaClient client;

  @override
  void initState() {
    super.initState();

    client = SolanaClient(
      rpcUrl: Uri.parse("https://devnet.helius-rpc.com/?api-key=0dc632a6-47ba-430d-9abb-dbbdc036cd92"),
      websocketUrl: Uri.parse("wss://devnet.helius-rpc.com/?api-key=0dc632a6-47ba-430d-9abb-dbbdc036cd92"),
    );

    // super.initState();

    final walletController = TextEditingController();
    final amountController = TextEditingController();
    AuthorizationResult? result;
  }

  bool isWalletConnected = false;

  // void connectWallet() async {
  //   scenario = await LocalAssociationScenario.create();
  //   scenario.startActivityForResult(null).ignore();
  //   final mwaClient = await scenario.start();
  //   authResult = await mwaClient.authorize(
  //     identityName: 'Test App',
  //     identityUri: Uri.parse("https://placeholder.com"),
  //     iconUri: Uri.parse("favicon"),
  //     cluster: 'devnet',
  //   );
  //   if (authResult?.publicKey != null) {
  //     setState(() => isWalletConnected = true);
  //   }
  //   print("Wallet Connected: ${authResult?.accountLabel}");
  //   print("Wallet Address: ${base58encode(authResult?.publicKey.toList() ?? [])}");
  //   scenario.close();
  // }


  void connectWallet() async {
    if (Platform.isAndroid) {
      // Android flow
      scenario = await LocalAssociationScenario.create();
      scenario.startActivityForResult(null).ignore();
      final mwaClient = await scenario.start();
      authResult = await mwaClient.authorize(
        identityName: 'Test App',
        identityUri: Uri.parse("https://placeholder.com"),
        iconUri: Uri.parse("favicon"),
        cluster: 'devnet',
      );
      if (authResult?.publicKey != null) {
        setState(() => isWalletConnected = true);
      }
      print("Wallet Connected: ${authResult?.accountLabel}");
      print("Wallet Address: ${base58encode(authResult?.publicKey.toList() ?? [])}");
      scenario.close();
    } else if (Platform.isIOS) {
      // iOS flow using Phantom
      print(">> called");
      PhantomConnector().connectPhantomWallet((pubkey) {
        print(">> $pubkey");
        setState(() {
          if (authResult?.publicKey != null) {
                setState(() => isWalletConnected = true);
              }
          isWalletConnected = true;
          authResult = AuthorizationResult(
            publicKey: Uint8List.fromList(base58decode(pubkey)),
            authToken: '', // not used for Phantom
            accountLabel: 'Phantom',
            walletUriBase: null,
          );
        });
        print("Wallet Connected (iOS): $pubkey");
      });
    }
  }

  Future<bool> _doReauthroize(MobileWalletAdapterClient mwaClient) async {
    try {
      final reauthorized = await mwaClient.reauthorize(
          identityUri: Uri.parse("https://placeholder.com"),
          iconUri: Uri.parse("favicon.ico"),
          identityName: "Workshop",
          authToken: authResult!.authToken
      );
      return reauthorized?.publicKey !=null;
    } catch (err) {
      return false;
    }
  }

  void disconnectWallet() {
    if (authResult != null) {
      try {
        mwaClient.deauthorize(authToken: authResult!.authToken);
      } catch (_) {}
      authResult = null;
    }
    setState(() {
      isWalletConnected = false;
    });
  }

  Future<void> sendSolana() async {
    try {
      if (!isWalletConnected || authResult == null  ) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You are not authroized")));
        return;
      }

      if (Platform.isIOS) {
        await PhantomTransfer.sendSolFromPhantom(
          context: context,
          fromAddress: base58encode(authResult!.publicKey.toList()),
          toAddress: "9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ",
          lamports: (0.01 * lamportsPerSol).toInt(),
        );
      }
      else {
        final amount = 0.01;
        final reciever = Ed25519HDPublicKey.fromBase58("9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ");
        scenario = await LocalAssociationScenario.create();
        scenario.startActivityForResult(null).ignore();
        final mwaClient = await scenario.start();
        if (!await _doReauthroize(mwaClient)) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Reauthrozation failed")));
          await scenario.close();
          return;
        }
        final signer = Ed25519HDPublicKey(authResult!.publicKey);
        final blockhash = (await client.rpcClient.getLatestBlockhash()).value.blockhash;
        final instruction = SystemInstruction.transfer(
          fundingAccount: signer,
          recipientAccount: reciever,
          lamports: (amount * lamportsPerSol).toInt(),
        );
        final message = Message(
            instructions: [instruction]
        ).compile(recentBlockhash: blockhash, feePayer: signer);
        final signedTx = SignedTx(
          compiledMessage: message,
          signatures: [Signature(List.filled(64, 0), publicKey: signer)],
        );
        final serializeTx = Uint8List.fromList(signedTx.toByteArray().toList());
        final signResult = await mwaClient.signTransactions(
          transactions: [serializeTx],
        );
        if (signResult.signedPayloads.isEmpty) {
          throw Exception("No signed payloads were returned");
        }
        final signature = await client.rpcClient.sendTransaction(
            base64.encode(signResult.signedPayloads[0]),
            preflightCommitment: Commitment.confirmed
        );
        print("transaction successfully ${signature}");
        print("✅ SOL Transferred Successfully: $signature");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ SOL Transferred Successfully $signature")),
        );
        await scenario.close();
      }
    } catch (err) {
      print("error while transferring the SOL $err");
    }
  }

  Future<void> sendOppiTokens() async {
    try {
      if (!isWalletConnected || authResult == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You are not authorized")),
        );
        return;
      }
      final amount = 1;
      final tokenDecimals = 9;
      final tokenMint = Ed25519HDPublicKey.fromBase58('BXxnX1n7xYV2e8VMPhaXX2mY8CoXzB5vi3JWFavbLfjA');
      final receiverWallet = Ed25519HDPublicKey.fromBase58('9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ');
      scenario = await LocalAssociationScenario.create();
      scenario.startActivityForResult(null).ignore();
      final mwaClient = await scenario.start();
      if (!await _doReauthroize(mwaClient)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reauthorization failed")),
        );
        await scenario.close();
        return;
      }
      final signer = Ed25519HDPublicKey(authResult!.publicKey);
      final blockhash = (await client.rpcClient.getLatestBlockhash()).value.blockhash;
      final senderATA = await findAssociatedTokenAddress(owner: signer, mint: tokenMint);
      final receiverATA = await findAssociatedTokenAddress(owner: receiverWallet, mint: tokenMint);
      print("senderATA $senderATA");
      print("receiverATA $receiverATA");
      print("here1");
      final instructions = <Instruction>[];
      print("here 2");
      print("here 3");
      print("senderATA base58: ${senderATA.toBase58()}");
      print("senderATA length: ${senderATA.toBase58().length}");
      final senderAccountInfo = await client.rpcClient.getAccountInfo(
        senderATA.toBase58(),
        commitment: Commitment.confirmed,
      );
      print("senderAccountInfo $senderAccountInfo");

      // if (senderAccountInfo == null) {
      //   print("Sender ATA not found, creating a new one...");
      //   final createSenderATAInstruction = AssociatedTokenAccountInstruction.createAccount(
      //     funder: signer,
      //     address: senderATA,
      //     owner: signer,
      //     mint: tokenMint,
      //   );
      //   instructions.add(createSenderATAInstruction);
      // }

      // ✅ Create receiver ATA if needed
      // final receiverAccountInfo = await client.rpcClient.getAccountInfo(
      //   receiverATA.toBase58(),
      //   commitment: Commitment.confirmed,
      // );
      // if (receiverAccountInfo == null) {
      //   print("Reciever ATA is not found, creating a newer one");
      //   final createReceiverATAInstruction = AssociatedTokenAccountInstruction.createAccount(
      //     funder: signer,
      //     address: receiverATA,
      //     owner: receiverWallet,
      //     mint: tokenMint,
      //   );
      //   instructions.add(createReceiverATAInstruction); // ✅ This was missing before
      // }
      print("adding the transactions");
      final transferInstruction = TokenInstruction.transfer(
        source: senderATA,
        destination: receiverATA,
        owner: signer,
        amount: (amount * lamportsPerSol).toInt(),
      );
      instructions.add(transferInstruction);
      print("transferInstruction ${transferInstruction}");
      final message = Message(instructions: instructions).compile(
        recentBlockhash: blockhash,
        feePayer: signer,
      );
      print("message txn $message");
      final signedTx = SignedTx(
        compiledMessage: message,
        signatures: [Signature(List.filled(64, 0), publicKey: signer)],
      );
      final serializedTx = Uint8List.fromList(signedTx.toByteArray().toList());
      print("signedTx $signedTx");
      final signResult = await mwaClient.signTransactions(transactions: [serializedTx]);
      if (signResult.signedPayloads.isEmpty) {
        throw Exception("No signed payloads returned");
      }
      print("signResult ${signResult}");

      final txSignature = await client.rpcClient.sendTransaction(
        base64.encode(signResult.signedPayloads[0]),
        preflightCommitment: Commitment.confirmed,
      );
      print("✅ SPL token transfer successful: $txSignature");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("✅ Token sent! Signature: $txSignature")),
      );
      await scenario.close();
    } catch (err) {
      print("❌ Error in SPL token transfer: $err");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $err")),
      );
      await scenario?.close();
    }
  }

  Future<void> sendSplTokens () async {
    try {
      scenario = await LocalAssociationScenario.create();
      scenario.startActivityForResult(null).ignore();
      final mwaClient = await scenario.start();
      if (!await _doReauthroize(mwaClient)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Reauthorization failed")),
        );
        await scenario.close();
        return;
      }
      final signer = Ed25519HDPublicKey(authResult!.publicKey);
      final blockhash = (await client.rpcClient.getLatestBlockhash()).value.blockhash;
      final mint = Ed25519HDPublicKey.fromBase58("BXxnX1n7xYV2e8VMPhaXX2mY8CoXzB5vi3JWFavbLfjA");
      final receiver = Ed25519HDPublicKey.fromBase58("9dDzzj6ztgnmcqM25yD4odBsqq7JVvwMNStfp6rrQ9VJ");
      print(mint);
      print('blockhash ${blockhash}');
      final instructions = <Instruction>[];
      final senderAta = await findAssociatedTokenAddress(owner: signer, mint: mint);
      final receiverAta = await findAssociatedTokenAddress(owner: receiver, mint: mint);
      final amount = 1;

      final ix = TokenInstruction.transfer(
        source: senderAta,
        destination: receiverAta,
        owner: signer,
        amount: (amount * lamportsPerSol).toInt(),
      );
      instructions.add(ix);
      final message = Message(instructions: instructions).compile(
        recentBlockhash: blockhash,
        feePayer: signer,
      );
      final signedTx = SignedTx(
        compiledMessage: message,
        signatures: [Signature(List.filled(64, 0), publicKey: signer)],
      );
      final serializedTx = Uint8List.fromList(signedTx.toByteArray().toList());
      print("signedTx $signedTx");
      final signResult = await mwaClient.signTransactions(transactions: [serializedTx]);
      if (signResult.signedPayloads.isEmpty) {
        throw Exception("No signed payloads returned");
      }
      print("signResult ${signResult}");
      //
      final txSignature = await client.rpcClient.sendTransaction(
        base64.encode(signResult.signedPayloads[0]),
        preflightCommitment: Commitment.confirmed,
      );
      //
      print("✅ Oppi token transfer successful: $txSignature");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(" ✅ Oppi token transferred successfully : $txSignature")),
      );
      print("txSignature $txSignature");
      await scenario.close();
    } catch (err) {
      print("error ${err}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Connect Wallet')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: connectWallet,
                child: Text('Connect Wallet'),
              ),
              SizedBox(height: 20),
              isWalletConnected && authResult?.publicKey != null
                  ? Text(
                'Wallet Address: ${base58encode(authResult!.publicKey.toList())}',
                style: TextStyle(fontSize: 16),
              )
                  : Text(
                'Please connect your wallet first',
                style: TextStyle(fontSize: 16, color: Colors.red),
              ),
              SizedBox(height: 20),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: disconnectWallet,
                child: Text('Disconnect Wallet'),
              ),
              ElevatedButton(
                onPressed: sendSolana,
                child: Text('SEND SOL 0.01'),
              ),
              // ElevatedButton(
              //     onPressed: sendOppiTokens,
              //     child: Text('SEND OPPI TOKENS')
              // ),
              ElevatedButton(
                  onPressed: sendSplTokens,
                  child: Text('SEND SPL TOKENS')
              )
            ],
          ),
        ),
      ),
    );
  }
}

class PhantomConnector {
  final String redirectUri = 'test5wallet://phantom';// Use same in Info.plist
  final String dappUrl = 'https://example.com';
  final String cluster = 'devnet';

  final appLink = AppLinks();

  String _generateRandomKey() {
    final rand = Random.secure();
    final bytes = Uint8List(32)..setAll(0, List.generate(32, (_) => rand.nextInt(256)));
    return base58encode(bytes);
  }

  Future<void> connectPhantomWallet(Function(String pubkey) onConnect) async {
    final nonce = _generateRandomKey();
    print(">> called 1");

    final Uri phantomUri = Uri.https('phantom.app', '/ul/v1/connect', {
      'app_url': dappUrl,
      'redirect_link': redirectUri,
      'cluster': cluster,
      'dapp_encryption_public_key': nonce,
    });
    print(">> called 2");
    if (await canLaunchUrl(phantomUri)) {
      print(">> called 3");
      await launchUrl(phantomUri, mode: LaunchMode.externalApplication);
      print(">> called 4");
    } else {
      throw 'Could not launch Phantom';
    }

    appLink.uriLinkStream.listen((uri) {
      print(">> called 6");
      print(">> data : $uri");
      print(">> data : ${uri.scheme}");
      if (uri.scheme == 'test5wallet') {
      print(">> called 7");
      print(">> dataQ : ${uri.queryParameters}");
        final pubkey = uri.queryParameters[Platform.isIOS ? 'phantom_encryption_public_key' : 'public_key'];
      print(">> pubkey : $pubkey");
        if (pubkey != null) {
          onConnect(pubkey);
        }
      }
    });
  }
}

class PhantomTransfer {
  static final _redirect = 'test5wallet://phantom';
  static final _cluster = 'devnet';
  static final _dappUrl = 'https://example.com';

  static final appLink = AppLinks();

  static String _generateNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base58encode(Uint8List.fromList(bytes));
  }

  static Future<void> sendSolFromPhantom({
    required BuildContext context,
    required String fromAddress,
    required String toAddress,
    required int lamports,
  }) async {
    try {
      final recentBlockhash = await _getLatestBlockhash();
      final instruction = SystemInstruction.transfer(
        fundingAccount: Ed25519HDPublicKey.fromBase58(fromAddress),
        recipientAccount: Ed25519HDPublicKey.fromBase58(toAddress),
        lamports: lamports,
      );

      final message = Message.only(instruction);
      final compiled = message.compile(
        recentBlockhash: recentBlockhash,
        feePayer: Ed25519HDPublicKey.fromBase58(fromAddress),
      );

      final serializedMessage = base64.encode(
        Uint8List.fromList(compiled.toByteArray().toList()),
      );


      final nonce = _generateNonce();

      final Uri deepLink = Uri.https('phantom.app', '/ul/v1/signAndSendTransaction', {
        'phantom_encryption_public_key': nonce,
        'redirect_link': _redirect,
        'payload': serializedMessage,
        'cluster': _cluster,
        'app_url': _dappUrl,
      });

      print('Launching Phantom with link: $deepLink');
      if (!await launchUrl(deepLink, mode: LaunchMode.externalApplication)) {
        throw Exception("Could not launch Phantom");
      }

      appLink.uriLinkStream.listen((Uri? uri) {
        if (uri != null && uri.scheme == "test5wallet") {
          final txSignature = uri.queryParameters["signature"];
          if (txSignature != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("✅ Transaction Success: $txSignature")),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("❌ Transaction failed or canceled")),
            );
          }
        }
      });
    } catch (e) {
      print("Error launching Phantom transaction: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    }
  }

  static Future<String> _getLatestBlockhash() async {
    final rpcClient = RpcClient("https://api.devnet.solana.com");
    final hash = await rpcClient.getLatestBlockhash();
    return hash.value.blockhash;
  }
}
