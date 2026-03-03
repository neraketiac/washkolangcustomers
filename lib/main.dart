import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:washkolangcustomer/enterloyaltycode.dart';
import 'firebase_options.dart';

late FirebaseFirestore firestore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Firebase

  // 🔹 MAIN project
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: EnterLoyaltyCode(),
    );
  }
}
