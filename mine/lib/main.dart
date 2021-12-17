import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Katzrdum Mine',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Katzrdum Mine Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final Future<FirebaseApp> _initialization = Firebase.initializeApp();
  DocumentReference<Map<String, dynamic>>? _docRef;
  Stream<int>? _counter;

  @override
  void initState() {
    super.initState();
    _setupFirestore();
  }

  void _setupFirestore() async {
    await _initialization;
    final docRef =
        FirebaseFirestore.instance.collection('interest').doc('expressions');
    final counter = docRef.snapshots().map((event) {
      final data = event.data();
      final int count = data == null ? 0 : data['count'];
      return count;
    });
    setState(() {
      _counter = counter;
      _docRef = docRef;
    });
  }

  void _showMyDialog() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Expression of Interest'),
          content: SingleChildScrollView(
            child: ListBody(
              children: const <Widget>[
                Text('Express your desire to see this happen!'),
                Text(
                    'Would you like to sign in with Google to receive email updates?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Yes'),
              onPressed: () {
                Navigator.of(context).pop();
                _expressInterest(true);
              },
            ),
            TextButton(
              child: const Text('No'),
              onPressed: () {
                Navigator.of(context).pop();
                _expressInterest(false);
              },
            ),
          ],
        );
      },
    );
  }

  void _expressInterest(bool google) async {
    if (google) {
      final signIn =
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      final email = signIn.user?.email;
      final emailsDocRef = FirebaseFirestore.instance.collection('interest').doc('emails');
      if (email != null) {
        await emailsDocRef.update({'emails': FieldValue.arrayUnion([email])});
      }
    } else {
      await FirebaseAuth.instance.signInAnonymously();
    }
    final docRef = _docRef;
    if (docRef != null) {
      await docRef.update({'count': FieldValue.increment(1)});
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            final children = <Widget>[
              Text(
                'UNDER\nCONSTRUCTION',
                style: Theme.of(context).textTheme.headline2,
                textAlign: TextAlign.center,
              ),
              Text(
                'Download and configure software for Google Glass',
                style: Theme.of(context).textTheme.headline3,
                textAlign: TextAlign.center,
              ),
              Text(
                'Expressions of interest:',
                style: Theme.of(context).textTheme.headline3,
                textAlign: TextAlign.center,
              ),
            ];
            final counter = _counter;
            if (counter != null) {

              children.add(
                StreamBuilder<int>(stream: counter, builder: (context, snapshot) =>
                Text(
                  (snapshot.data ?? 0).toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headline4,
                )
              ));
            }
            return Scaffold(
              appBar: AppBar(
                title: Text(widget.title),
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: children,
                ),
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: () => _showMyDialog(),
                tooltip: 'Interest',
                child: const Icon(Icons.add),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        });
  }
}
