import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:washkolangcustomer/features/loyalty/enterloyaltycode.dart';
import 'package:washkolangcustomer/features/home/main_images.dart';
import 'package:washkolangcustomer/features/pickup/pickup_booking_this_week.dart';
import 'package:washkolangcustomer/features/rider/view_rider_location.dart';
import 'package:washkolangcustomer/features/home/welcome_images.dart';
import 'package:web/web.dart' as web;

const _kSubCollection = 'push_subscriptions';
const _kWatchers = 'rider_watchers';
const _kVapidKey =
    'BFLfvLXFkeaA_h1fn-nEpGU9kMfIVpgZyEM5lmkiihEZ__sJYPT_yhRiyy6Ikm2x1tDJUgWPI7m78oQH235pxuo';
const _kPreviousTokenKey = 'fcm_token';

Future<void> _saveTokenToFirestore(String token) async {
  final prevToken = web.window.localStorage.getItem(_kPreviousTokenKey);
  if (prevToken != null && prevToken != token) {
    await FirebaseFirestore.instance
        .collection(_kSubCollection)
        .doc(prevToken)
        .delete();
  }
  web.window.localStorage.setItem(_kPreviousTokenKey, token);
  await FirebaseFirestore.instance.collection(_kSubCollection).doc(token).set({
    'token': token,
    'subscribedAt': Timestamp.now(),
    'platform': 'web',
  });
}

Future<void> _removeTokenFromFirestore(String token) async {
  web.window.localStorage.removeItem(_kPreviousTokenKey);
  await FirebaseFirestore.instance
      .collection(_kSubCollection)
      .doc(token)
      .delete();
}

class MainWelcome extends StatefulWidget {
  const MainWelcome({super.key});

  @override
  State<MainWelcome> createState() => _MainWelcomeState();
}

class _MainWelcomeState extends State<MainWelcome> {
  bool _notifyChecked = false;
  bool _notifyLoading = false;
  String? _notifyStatus;
  String? _cachedToken;
  bool _mapMaximized = false;
  final ScrollController _scrollController = ScrollController();
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  Timer? _watcherTimer;

  @override
  void initState() {
    super.initState();
    _registerWatcher();
    _watcherTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _updateLastSeen(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreNotifyState();
      WelcomeImagesViewer.show(context);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _watcherTimer?.cancel();
    FirebaseFirestore.instance
        .collection(_kWatchers)
        .doc(_sessionId)
        .get()
        .then((doc) {
          if (doc.exists) {
            FirebaseFirestore.instance.collection('rider_watchers_history').add(
              {
                ...doc.data()!,
                'watcherId': _sessionId,
                'clearedAt': Timestamp.now(),
              },
            );
            doc.reference.delete();
          }
        });
    super.dispose();
  }

  Future<void> _registerWatcher() async {
    String? publicIp;
    try {
      final resp = await http.get(
        Uri.parse('https://api.ipify.org?format=json'),
      );
      if (resp.statusCode == 200)
        publicIp = jsonDecode(resp.body)['ip'] as String?;
    } catch (_) {}
    final ua = web.window.navigator.userAgent;
    final lang = web.window.navigator.language;
    final screen = web.window.screen;
    final tz = DateTime.now().timeZoneName;
    await FirebaseFirestore.instance
        .collection(_kWatchers)
        .doc(_sessionId)
        .set({
          'joinedAt': Timestamp.now(),
          'lastSeen': Timestamp.now(),
          if (publicIp != null) 'publicIp': publicIp,
          'userAgent': ua,
          'language': lang,
          'screenResolution': '${screen.width}x${screen.height}',
          'timezone': tz,
          'platform': web.window.navigator.platform,
        });
  }

  Future<void> _updateLastSeen() async {
    try {
      await FirebaseFirestore.instance
          .collection(_kWatchers)
          .doc(_sessionId)
          .set({'lastSeen': Timestamp.now()}, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _restoreNotifyState() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized)
        return;
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: _kVapidKey,
      );
      if (token == null) return;
      _cachedToken = token;
      final doc = await FirebaseFirestore.instance
          .collection(_kSubCollection)
          .doc(token)
          .get();
      if (mounted) setState(() => _notifyChecked = doc.exists);
    } catch (_) {}
  }

  Future<String?> _getToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized)
        return null;
      return await FirebaseMessaging.instance.getToken(vapidKey: _kVapidKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> _toggleNotify(bool val) async {
    setState(() {
      _notifyLoading = true;
      _notifyStatus = null;
    });
    try {
      final token = _cachedToken ?? await _getToken();
      if (token == null) {
        if (val)
          setState(() {
            _notifyStatus =
                'Notifications blocked. To enable: click the lock icon in your browser address bar, then Notifications, then Allow, then refresh.';
            _notifyChecked = false;
          });
        return;
      }
      _cachedToken = token;
      if (val) {
        await _saveTokenToFirestore(token);
        setState(() {
          _notifyChecked = true;
          _notifyStatus = "You'll be notified when the rider is available.";
        });
      } else {
        await _removeTokenFromFirestore(token);
        setState(() {
          _notifyChecked = false;
          _notifyStatus = 'Notifications turned off.';
        });
      }
    } catch (e) {
      setState(() => _notifyStatus = 'Error: $e');
    } finally {
      if (mounted) setState(() => _notifyLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // scrollable content
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // images section
                          const MainImages(),
                          const SizedBox(height: 10),

                          // toolbar
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () => web.window.open(
                                    'https://m.me/WashkoLangLaundryHub',
                                    '_blank',
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1877F2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          '💬',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Messenger',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const EnterLoyaltyCode(),
                                    ),
                                  ),
                                  child: const Text(
                                    'Loyalty Card 👉 💳',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF3A86FF),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // notify + maximize row
                          Row(
                            children: [
                              const SizedBox(width: 8),
                              _notifyLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Checkbox(
                                      value: _notifyChecked,
                                      onChanged: (v) =>
                                          _toggleNotify(v ?? false),
                                      activeColor: Colors.blueAccent,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      visualDensity: VisualDensity.compact,
                                    ),
                              GestureDetector(
                                onTap: () => _toggleNotify(!_notifyChecked),
                                child: Text(
                                  'Notify me when rider is available.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _notifyChecked
                                        ? Colors.blueAccent
                                        : Colors.blueGrey,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Material(
                                color: Colors.blueGrey.shade700,
                                borderRadius: BorderRadius.circular(8),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () {
                                    final maximizing = !_mapMaximized;
                                    setState(() => _mapMaximized = maximizing);
                                    if (maximizing) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            _scrollController.animateTo(
                                              _scrollController
                                                  .position
                                                  .maxScrollExtent,
                                              duration: const Duration(
                                                milliseconds: 400,
                                              ),
                                              curve: Curves.easeOut,
                                            );
                                          });
                                    }
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _mapMaximized
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _mapMaximized
                                              ? 'Minimize'
                                              : 'Maximize',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_notifyStatus != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                              child: Text(
                                _notifyStatus!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _notifyChecked
                                      ? Colors.green.shade700
                                      : Colors.blueGrey,
                                ),
                              ),
                            ),
                          const SizedBox(height: 6),

                          // rider map
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: SizedBox(
                              width: double.infinity,
                              height: _mapMaximized ? screenH * 0.75 : 220,
                              child: const RiderLocationWidget(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // price + pickup buttons always at bottom
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => WelcomeImagesViewer.show(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF66BB6A),
                                    Color(0xFF388E3C),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.price_change,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Price',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    const PickupBookingThisWeekScreen(),
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF42A5F5),
                                    Color(0xFF1E88E5),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blueAccent.withValues(
                                      alpha: 0.3,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.local_laundry_service,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Pickup',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
