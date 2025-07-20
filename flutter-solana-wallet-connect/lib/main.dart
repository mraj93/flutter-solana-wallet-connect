import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:solana/base58.dart';
import 'package:solana_mobile_client/solana_mobile_client.dart';
import 'package:solana/solana.dart';
import 'package:solana/encoder.dart';

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
      rpcUrl: Uri.parse("PASTE_RPC_URL"),
      websocketUrl: Uri.parse("PASTE_WSS_URL"),
    );

    // super.initState();

    final walletController = TextEditingController();
    final amountController = TextEditingController();
    AuthorizationResult? result;
  }

  bool isWalletConnected = false;

  void connectWallet() async {
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
    } catch (err) {
      print("error while transferring the SOL");
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

  Future<void> sendSplTokens (
  ) async {
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
      final mint = Ed25519HDPublicKey.fromBase58('PASTE_SPL_TOKEN_ADDRESS');
      final receiver = Ed25519HDPublicKey.fromBase58('PASTE_RECIPIENT_ADDRESS');
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