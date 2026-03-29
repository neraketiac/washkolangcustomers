import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:washkolangcustomer/view_rider_location.dart';
import 'firebase_options.dart';

/// Default Firestore — loyalty, rider_location, push_subscriptions, etc.
late FirebaseFirestore firestore;

/// Secondary Firestore — Jobs_done & Jobs_completed
late FirebaseFirestore forthFirestore;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Primary app (zpos-d985c)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  firestore = FirebaseFirestore.instance;

  // Suppress FCM foreground auto-display — SW handles all notifications
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: false,
    sound: false,
  );

  // Secondary app (signuptest-53277) — jobs database
  final forthApp = await Firebase.initializeApp(
    name: 'forthWeb',
    options: DefaultFirebaseOptions.forthWeb,
  );
  forthFirestore = FirebaseFirestore.instanceFor(app: forthApp);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RiderLocationScreen(),
    );
  }
}
