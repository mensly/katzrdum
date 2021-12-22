import 'package:flutter/foundation.dart';
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
  late ServerSocket _server;
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
    _server.close();
    _broadcasting = false;
  }

  void _runServer() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _portTcp);
    _server.listen((client) => _handleConnection(client));
    _broadcast();
  }

  void _broadcast() async {
    var sender = await UDP.bind(Endpoint.any(port: const Port(_portUdp)));
    // TODO: Generate a key pair
    const publicKey = "MOCK";
    _privateKey = "MOCK";
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
        setState(() {
          // TODO: parse as JSON to show UI
          _config = (_config ?? "") + message;
        });
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

  @override
  Widget build(BuildContext context) {
    List<Widget> body;
    final client = _client;
    final config = _config;
    if (kIsWeb) {
      body = [
        Image.asset('assets/balrog_wink.png', width: 320, height: 320),
        const SizedBox(
            width: 400,
            child: Text(
                'To securely communicate with your connected device, we need to '
                'do things a website isn\'t allowed to do, please install '
                'Katzrdum Mine on your Android or iOS device')),
      ];
    } else if (client != null && config != null) {
      // Show config UI
      body = [Text(config)];
    } else {
      final loadingText = client == null
          ? 'Cercant Katzrdum a la xarxa local d\'ordinadors…'
          : 'S\'està carregant la configuració mitjançant un sòcol segur…';
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
        ));
  }
}
