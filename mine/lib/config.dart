import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:udp/udp.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const _portUdp = 21055;
  static const _portTcp = 24990;
  Socket? _client;
  var _broadcasting = false;
  String? _privateKey;
  String? _config; // TODO: Load as JSON to build UI

  @override
  void initState() {
    super.initState();
    _runServer();
  }

  @override
  void dispose() {
    super.dispose();
    _disconnect();
    _broadcasting = false;
  }

  void _runServer() async {
    // FIXME: This doesn't work on web COMPUTER SAYS NO
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, _portTcp);
    server.listen((client) => _handleConnection(client));
    // TODO: Generate a GPG key pair
    const publicKey = "MOCK";
    _privateKey = "MOCK";
    var sender = await UDP.bind(Endpoint.any(port: const Port(_portUdp)));

    _broadcasting = true;
    while (_broadcasting) {
      await sender.send(publicKey.codeUnits,
          Endpoint.broadcast(port: const Port(_portUdp)));
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
    client.listen(
      (Uint8List data) async {
        final message = String.fromCharCodes(data);
        setState(() {
          // TODO: wait for matched {} then parse config JSON
          _config = (_config ?? "") + message;
        });
      },
      onError: (error) {
        _disconnect();
      },
      onDone: () {
        _disconnect();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> body;
    final client = _client;
    final config = _config;
    if (client != null && config != null) {
      // Show config UI
      body = [Text(config)];
    } else {
      final loadingText = client == null ?
        'Cercant Katzrdum a la xarxa local d\'ordinadors…' :
        'S\'està carregant la configuració mitjançant un sòcol segur…';
      body = [
        Image.asset('assets/balrog_wink.png', width: 320, height: 320),
        Center(child: Text(loadingText)),
        const Padding(
          padding: EdgeInsets.all(64.0),
          child: CircularProgressIndicator(),
        )
      ];
    }
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: body,
          ),
        )
    );
  }
}
