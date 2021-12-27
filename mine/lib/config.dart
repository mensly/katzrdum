import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:katzrdum/crypto.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:udp/udp.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Object? _privateKey;
  // TODO: Model class for config that includes fields and key
  List<String>? _config;
  Object? _clientKey;

  @override
  void initState() {
    super.initState();
    // FIXME: Something is blocking the main thread
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

  void _broadcast() async {
    var sender = await UDP.bind(Endpoint.any(port: const Port(_portUdp)));
    final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 4096);
    final publicKey = encodePublicKey(keyPair.publicKey);
    // TODO: Remove this quick test of encrypt/decrypt
    final originalMessage = "Hello Brave New World";
    print(originalMessage);
    print(publicKey);
    final cipherMessage = encrypt(originalMessage, keyPair.publicKey);
    print(cipherMessage);
    final decodedMessage = decrypt(cipherMessage, keyPair.privateKey);
    print(decodedMessage);

    final code = calculateCode(publicKey);
    setState(() {
      _code = code;
    });
    _privateKey = keyPair.privateKey;
    _broadcasting = true;
    while (_broadcasting) {
      await sender.send(
          publicKey.codeUnits, Endpoint.broadcast(port: const Port(_portUdp)));
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
      (Uint8List data) async {
        final message = String.fromCharCodes(data);
        try {
          // TODO: Properly parse different fields
          // netcat
          // Sample data: {"fields":[{"name":"foo"},{"name":"bar"},"key":"AAAAB3NzaC1yc2EAAAADAQABAAABgQCzivj8BMOT9Uq3SqC+2DxAWlGN4QslLq+NA0yY8467CKJWgKb1uY+28zLn4FbwHAvTWR5TyDjPQFJUeiQckkhFSf06RoWzJFNoHB6AKmMLTWTlvAukHNYXNKTpbT7u1QymAQeaWP1d7c8BumTBbbjT/lmfFQSQRyKfgGDosA5Xbt2QKCZiL7gX0ItPM4Z1X40O4ieKLTsXb/PrzE02wZQng09Kk2D8t66mPf4VCOmcd73qBh3nLACoN2wESOcMrsQmBzoMJSzP/YbGI26BbJleeysQ6WTovlfPGaJpe+vlknN7gcjzXp3gRH53AXU/QvPD8xCxCdW+r4mWjCMa/MbCPoWh0twJP3w1PjnWvO2XmBfOFSJSXpea23l7vO+6KikcF5y/02dnpjk7c26irrmjdaRXE0A8zyozh+vWgPFi5xB+fRiX6V0kd8ZIHSH/qYcUb5yknL1IIZWURN5pnl4M7kVSY1Ob4ekjQ+WJ0TvM+9a6H304Tvo8u5/GcYDZ3qE="]}
          final fields = <String>[];
          final decoded = jsonDecode(decrypt(message, _privateKey));
          final String clientKey = decoded['key'];
          for (final field in decoded['fields']) {
            final name = field['name'];
            fields.add(name);
          }
          setState(() {
            _clientKey = clientKey;
            _config = fields;
          });
        } catch (_) {
          // TODO: Handle json parsing errors etc
          setState(() {
            _config = ['Could not decode: ' + message];
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
    } else if (client != null && config != null) {
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
                  client: client,
                  clientKey: _clientKey,
                  name: config[index - 2]);
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
  const StringConfigWidget({Key? key, required this.client, required this.name, required this.clientKey})
      : super(key: key);

  // TODO: Use ConfigField class
  final String name;
  final Socket client;
  final Object? clientKey;

  void sendValue(String value) {
    client.writeln(encrypt('$name:$value', clientKey));
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