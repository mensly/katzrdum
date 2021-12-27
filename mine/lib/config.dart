import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:katzrdum/crypto.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:udp/udp.dart';
import 'package:url_launcher/url_launcher.dart';
import "package:pointycastle/export.dart" show RSAPrivateKey;

class ConfigPage extends StatefulWidget {
  const ConfigPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const _portUdp = 21055;
  static const _portTcp = 24990;
  late ServerSocket _server;
  Socket? _client;
  var _broadcasting = false;
  String? _code;
  String? _publicKey;
  RSAPrivateKey? _privateKey;
  Uint8List? _secretKey;
  Uint8List? _iv;
  // TODO: Model class for config that includes fields
  List<String>? _config;

  @override
  void initState() {
    super.initState();
    _runServer();
  }

  @override
  void dispose() {
    _server.close();
    _client?.close();
    _broadcasting = false;
    super.dispose();
  }

  void _runServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _portTcp);
    _server.listen((client) => _handleConnection(client));
    _broadcast();
  }

  Future<String> _generateKeys() async {
    final keyPair = await generateKeyPair();
    final publicKey = encodePublicKey(keyPair.publicKey);
    print('publicKey: $publicKey');

    final code = calculateCode(publicKey);
    _privateKey = keyPair.privateKey;
    _iv = calculateIv(publicKey);
    _broadcasting = true;
    setState(() {
      _code = code;
    });
    _publicKey = publicKey;
    return publicKey;
  }

  void _broadcast() async {
    var sender = await UDP.bind(Endpoint.any(port: const Port(_portUdp)));
    final publicKey = _publicKey ?? await _generateKeys();
    final data = utf8.encode(publicKey);
    while (_broadcasting) {
      await sender.send(data, Endpoint.broadcast(port: const Port(_portUdp)));
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _disconnect() {
    _client?.close();
    setState(() {
      _config = null;
      _client = null;
    });
  }

  void _handleConnection(Socket client) async {
    final privateKey = _privateKey;
    final iv = _iv;
    if (privateKey == null || iv == null) {
      return; // No key generated
    }
    if (_client != null) {
      // Already connected to a client
      client.close();
      return;
    }
    setState(() {
      _client = client;
      _config = null;
    });
    _broadcasting = false;
    client.listen(
      (Uint8List cipherData) async {
        var secretKey = _secretKey;
        if (secretKey == null) {
          print('cipherData: ${base64Encode(cipherData)}');
          secretKey = decryptSecretKey(cipherData, privateKey);
          setState(() {
            _secretKey = secretKey;
          });
          print('got secret key ${base64Encode(secretKey)}');
          print('got secret key ${utf8.decode(secretKey)}');
          return;
        }
        String? message;
        try {
          message = decryptString(cipherData, secretKey, iv);
          final fields = <String>[];
          final decoded = jsonDecode(message!);
          for (final field in decoded['fields']) {
            // TODO: Properly parse different fields
            final name = field['name'];
            fields.add(name);
          }
          setState(() {
            _config = fields;
          });
        } catch (e) {
          print('error receiving config: $e');
          // TODO: Handle json parsing errors etc
          setState(() {
            _config = ['Could not decode: ' + (message ?? String.fromCharCodes(cipherData)), e.toString()];
          });
        }
      },
      onError: (error) {
        _disconnect();
        _broadcast();
      },
      onDone: () {
        _disconnect();
        _broadcast();
      },
    );
  }

  void _downloadApk() async {
    // TODO: Get latest version from firebase
    await launch("https://mine.balrog.cat/app-release.apk");
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    final client = _client;
    final config = _config;
    final secretKey = _secretKey;
    final iv = _iv;
    if (kIsWeb) {
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Image.asset('assets/balrog_wink.png', width: 320, height: 320),
        const SizedBox(
            width: 400,
            child: Text(
              'To securely communicate with your connected device, we need to '
              'do things a website isn\'t allowed to do, please install '
              'Katzrdum Mine on your Android or iOS device',
              textAlign: TextAlign.center,
            )),
        MaterialButton(
            onPressed: () => _downloadApk(), child: const Text("Download APK"))
      ]);
    } else if (client != null && config != null && secretKey != null && iv != null) {
      // Show config UI
      body = ListView.builder(
          itemCount: config.length + 2,
          itemBuilder: (context, index) {
            switch (index) {
              case 0: return const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('Configure',
                  textAlign: TextAlign.center,
                  textScaleFactor: 1.5),
              );
              case 1: return const DividerWidget();
              default: return StringConfigWidget(
                  name: config[index - 2], client: client, secretKey: secretKey, iv: iv);
            }
          }
      );
    } else {
      final code = _code;
      final codeText = code == null ? '' : '\nCODE: $code';
      final loadingText = client == null
          ? 'Cercant Katzrdum a la xarxa local d\'ordinadors…' + codeText
          : 'S\'està carregant la configuració\nmitjançant un sòcol segur…';
      body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Image.asset('assets/balrog_wink.png', width: 320, height: 320),
        Center(child: Text(loadingText, textAlign: TextAlign.center)),
        const Padding(
          padding: EdgeInsets.all(64.0),
          child: CircularProgressIndicator(),
        )
      ]);
    }
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Center(child: body));
  }
}

// TODO: Move to separate subpackage
class StringConfigWidget extends StatefulWidget {
  const StringConfigWidget({Key? key, required this.name, required this.client,
    required this.secretKey, required this.iv})
      : super(key: key);

  // TODO: Use ConfigField class
  final String name;
  final Socket client;
  final Uint8List secretKey;
  final Uint8List iv;

  void sendValue(String value) {
    client.writeln(encryptString('$name:$value', secretKey, iv));
  }

  @override
  State<StringConfigWidget> createState() => _StringConfigWidgetState();
}

class _StringConfigWidgetState extends State<StringConfigWidget> {
  final _valueController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final label = widget.name;
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(label),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
              controller: _valueController,
              onSubmitted: (text) => widget.sendValue(text)),
        ),
        MaterialButton(
          onPressed: () => widget.sendValue(_valueController.text),
          color: Theme.of(context).buttonTheme.colorScheme!.background,
          child: const Text('Send'),
        ),
        const DividerWidget(),
      ]),
    );
  }
}

class DividerWidget extends StatelessWidget {
  const DividerWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
        height: 2.0,
        color: Theme.of(context).colorScheme.secondary
    );
  }
}