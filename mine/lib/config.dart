import 'dart:convert';

import 'package:basic_utils/basic_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:katzrdum/crypto.dart';
import 'package:katzrdum/fields.dart';
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
  static final _newLine = utf8.encode("\n")[0];
  late ServerSocket _server;
  Socket? _client;
  var _broadcasting = false;
  String? _code;
  String? _publicKey;
  RSAPrivateKey? _privateKey;
  Uint8List? _secretKey;
  Uint8List? _iv;
  // TODO: Model class for config that includes fields
  List<ConfigField>? _fields;

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
    debugPrint('publicKey: $publicKey');

    final code = calculateCode(publicKey);
    _privateKey = keyPair.privateKey;
    _iv = calculateIv(publicKey);
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
    _broadcasting = true;
    while (_broadcasting) {
      await sender.send(data, Endpoint.broadcast(port: const Port(_portUdp)));
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  void _disconnect() {
    _client?.close();
    setState(() {
      _fields = null;
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
      _fields = null;
    });
    _broadcasting = false;
    client.listen(
      (Uint8List cipherData) async {
        final secretKey =
            decryptSecretKey(cipherData.sublist(0, secretKeySize), privateKey);
        setState(() {
          _secretKey = secretKey;
        });
        String? message;
        try {
          message =
              decryptString(cipherData.sublist(secretKeySize), secretKey, iv);
          final fields = <ConfigField>[];
          final decoded = jsonDecode(message);
          for (final fieldData in decoded['fields']) {
            final field = ConfigField.parse(fieldData);
            if (field != null) {
              fields.add(field);
            }
          }
          setState(() {
            _fields = fields;
          });
        } catch (e) {
          debugPrint('error receiving config: $e');
          // TODO: Handle json parsing errors etc
        }
      },
      onError: (error) {
        debugPrint('tcp error $error');
        _disconnect();
        _broadcast();
      },
      onDone: () {
        debugPrint('done');
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
    final fields = _fields;
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
    } else if (client != null &&
        fields != null &&
        secretKey != null &&
        iv != null) {
      // Show config UI
      body = ListView.builder(
          itemCount: fields.length + 2,
          itemBuilder: (context, index) {
            switch (index) {
              case 0:
                return const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Configure',
                      textAlign: TextAlign.center, textScaleFactor: 1.5),
                );
              case 1:
                return const DividerWidget();
              default:
                return ConfigWidget(
                    field: fields[index - 2],
                    client: client,
                    secretKey: secretKey,
                    iv: iv);
            }
          });
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

class ConfigWidget extends StatefulWidget {
  const ConfigWidget(
      {Key? key,
      required this.field,
      required this.client,
      required this.secretKey,
      required this.iv})
      : super(key: key);

  final ConfigField field;
  final Socket client;
  final Uint8List secretKey;
  final Uint8List iv;

  void sendValue(dynamic value) {
    final message = '${field.name}:${field.encodeValue(value)}';
    final cipherMessage =
        base64Encode(encryptString(message, secretKey, iv).toList());
    debugPrint('message: $message');
    debugPrint('cipherMessage: $cipherMessage');
    client.writeln(cipherMessage);
    debugPrint('sent config message');
  }

  @override
  State<ConfigWidget> createState() {
    if (field is PasswordField) {
      return _PasswordConfigWidgetState();
    } else if (field is LongIntegerField) {
      return _LongIntegerConfigWidgetState();
    } else if (field is StringField) {
      return _StringConfigWidgetState();
    } else if (field is ColorField) {
      return _ColorConfigWidgetState();
    }
    throw Exception("Unsupported field type");
  }
}

abstract class _ConfigWidgetState extends State<ConfigWidget> {
  Widget buildInput(BuildContext context);
  dynamic getValue();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(widget.field.label),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: buildInput(context),
        ),
        MaterialButton(
          onPressed: () => widget.sendValue(getValue()),
          color: Theme.of(context).buttonTheme.colorScheme!.background,
          child: const Text('Send'),
        ),
        const DividerWidget(),
      ]),
    );
  }
}

class _StringConfigWidgetState extends _ConfigWidgetState {
  final _valueController = TextEditingController();

  @override
  getValue() => _valueController.text;

  @override
  Widget buildInput(BuildContext context) => TextField(
        controller: _valueController,
        onSubmitted: (text) => widget.sendValue(getValue()),
      );
}

class _PasswordConfigWidgetState extends _StringConfigWidgetState {
  @override
  Widget buildInput(BuildContext context) => TextField(
        controller: _valueController,
        obscureText: true,
        onSubmitted: (text) => widget.sendValue(getValue()),
      );
}

class _LongIntegerConfigWidgetState extends _ConfigWidgetState {
  final _valueController = TextEditingController();

  @override
  getValue() => int.parse(_valueController.text);

  @override
  Widget buildInput(BuildContext context) => TextField(
        controller: _valueController,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly
        ],
        onSubmitted: (text) => widget.sendValue(getValue()),
      );
}

class _ColorConfigWidgetState extends _ConfigWidgetState {
  late Color _color;

  @override
  void initState() {
    super.initState();
    setState(() {
      _color = (widget.field as ColorField).defaultColor;
    });
  }

  @override
  getValue() => _color;

  void _showDialog(BuildContext context) {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Choose Color'),
            contentPadding: const EdgeInsets.all(0),
            content: SingleChildScrollView(
              child: MaterialPicker(
                pickerColor: _color,
                onColorChanged: (color) {
                  setState(() {
                    _color = color;
                    Navigator.of(context).pop();
                  });
                },
                enableLabel: true,
                portraitOnly: true,
              ),
            ),
            actions: [
              TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop();
                  })
            ],
          );
        });
  }

  @override
  Widget buildInput(BuildContext context) => GestureDetector(
        child: Container(height: 50.0, color: _color),
        onTap: () => _showDialog(context),
      );
}

class DividerWidget extends StatelessWidget {
  const DividerWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
        height: 2.0, color: Theme.of(context).colorScheme.secondary);
  }
}
