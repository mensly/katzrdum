import 'package:flutter/material.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Image.asset('assets/balrog_wink.png', width: 320, height: 320,),
              const Center(child: Text('Cercant Katzrdum a la xarxa local d\'ordinadors…')),
              const Padding(
                padding: EdgeInsets.all(64.0),
                child: CircularProgressIndicator(),
              )
            ],
          ),
        )
    );
  }
}
