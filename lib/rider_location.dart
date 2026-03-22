import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const _kCollection = 'rider_location';
const _kDoc = 'current';
const _kSubCollection = 'push_subscriptions';
const _kVapidKey =
    'BFLfvLXFkeaA_h1fn-nEpGU9kMfIVpgZyEM5lmkiihEZ__sJYPT_yhRiyy6Ikm2x1tDJUgWPI7m78oQH235pxuo';
const _kPushServer = 'https://rider-push-server.onrender.com/send';

// ===================== NOTIFICATION HELPERS =====================

Future<void> _saveTokenToFirestore(String token) async {
  await FirebaseFirestore.instance.collection(_kSubCollection).doc(token).set({
    'token': token,
    'subscribedAt': Timestamp.now(),
    'platform': 'web',
  });
}

Future<void> _removeTokenFromFirestore(String token) async {
  await FirebaseFirestore.instance
      .collection(_kSubCollection)
      .doc(token)
      .delete();
}

Future<void> _notifyAllSubscribers() async {
  final snap = await FirebaseFirestore.instance
      .collection(_kSubCollection)
      .get();
  final tokens = snap.docs
      .map((d) => d.data()['token'])
      .whereType<String>()
      .toList();

  if (tokens.isEmpty) return;

  await http
      .post(
        Uri.parse(_kPushServer),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tokens': tokens,
          'title': '🛵 Rider is Available!',
          'body': 'Your rider is now online and sharing location.',
          'url': 'https://washkolang.online',
        }),
      )
      .then((response) {
        if (response.statusCode == 200) {
          print('FCM push successful: ${response.body}');
        } else {
          print('FCM push failed [${response.statusCode}]: ${response.body}');
        }
      });
}

// ===================== INLINE MAP WIDGET =====================

class RiderLocationWidget extends StatefulWidget {
  const RiderLocationWidget({super.key});

  @override
  State<RiderLocationWidget> createState() => _RiderLocationWidgetState();
}

// slot key → display label (same as pickup_booking.dart)
const _scheduleSlotLabels = {
  'slot7to9': '7am–9am',
  'slot9to10': '9am–10am',
  'slot10to12': '10am–12pm',
  'slot1to3': '1pm–3pm',
  'slot3to5': '3pm–5pm',
  'slot5to7': '5pm–7pm',
  'slot7to9pm': '7pm–9pm',
};
const _scheduleSlotEndHour = {
  'slot7to9': 9,
  'slot9to10': 10,
  'slot10to12': 12,
  'slot1to3': 15,
  'slot3to5': 17,
  'slot5to7': 19,
  'slot7to9pm': 21,
};

class _RiderLocationWidgetState extends State<RiderLocationWidget> {
  double? _lat;
  double? _lng;
  bool _loading = true;
  bool _offline = false;
  String? _lastUpdated;
  StreamSubscription? _sub;

  List<String> _todaySlots = [];
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _checkThenStream();
  }

  Future<void> _loadTodaySlots() async {
    final now = DateTime.now();
    final docId =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    setState(() => _loadingSlots = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Rider_schedule')
          .doc(docId)
          .get();
      if (!doc.exists) {
        if (mounted)
          setState(() {
            _todaySlots = [];
            _loadingSlots = false;
          });
        return;
      }
      final data = doc.data()!;
      final slots = <String>[];
      for (final entry in _scheduleSlotLabels.entries) {
        final key = entry.key;
        final label = entry.value;
        final enabled = data[key] == true;
        final endHour = _scheduleSlotEndHour[key] ?? 0;
        if (enabled && now.hour < endHour) {
          slots.add(label);
        }
      }
      if (mounted)
        setState(() {
          _todaySlots = slots;
          _loadingSlots = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _todaySlots = [];
          _loadingSlots = false;
        });
    }
  }

  Future<void> _checkThenStream() async {
    // Single read first — only open stream if rider is actually online
    final ref = FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc);

    final initial = await ref.get();
    if (!initial.exists) {
      if (mounted) {
        setState(() {
          _loading = false;
          _offline = true;
        });
      }
      _loadTodaySlots();
      return;
    }

    // Rider is online — now open the live stream
    _sub = ref.snapshots().listen((snap) {
      if (!snap.exists) {
        if (mounted) {
          setState(() {
            _lat = null;
            _lng = null;
            _offline = true;
          });
        }
        _loadTodaySlots();
        return;
      }
      final data = snap.data()!;
      final ts = data['updatedAt'] as Timestamp?;
      if (mounted) {
        setState(() {
          _lat = (data['lat'] as num?)?.toDouble();
          _lng = (data['lng'] as num?)?.toDouble();
          _loading = false;
          _offline = false;
          if (ts != null) {
            final d = ts.toDate().toLocal();
            _lastUpdated =
                '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_offline || _lat == null || _lng == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.electric_moped,
                size: 40,
                color: Colors.blueGrey,
              ),
              const SizedBox(height: 8),
              const Text(
                'Rider is not currently sharing location.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingSlots)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_todaySlots.isNotEmpty) ...[
                const Text(
                  "Today's rider schedule:",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.center,
                  children: _todaySlots
                      .map(
                        (slot) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Text(
                            slot,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Check back during these times.',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ] else
                const Text(
                  'No more rider slots available today.\nCheck back tomorrow.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_lastUpdated != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Last updated: $_lastUpdated',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ),
        Expanded(
          child: _MapIframe(lat: _lat!, lng: _lng!),
        ),
      ],
    );
  }
}

// ===================== MAP IFRAME =====================

class _MapIframe extends StatefulWidget {
  final double lat;
  final double lng;
  const _MapIframe({required this.lat, required this.lng});

  @override
  State<_MapIframe> createState() => _MapIframeState();
}

class _MapIframeState extends State<_MapIframe> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    _viewId = 'rider-map-${DateTime.now().millisecondsSinceEpoch}';
    final iframe = web.HTMLIFrameElement()
      ..src =
          'https://maps.google.com/maps?q=${Uri.encodeComponent("Rider+🛵")}@${widget.lat},${widget.lng}&z=16&output=embed'
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true;
    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) => iframe);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }
}

// ===================== FULL SCREEN MAP PAGE =====================

class RiderLocationScreen extends StatefulWidget {
  const RiderLocationScreen({super.key});

  @override
  State<RiderLocationScreen> createState() => _RiderLocationScreenState();
}

class _RiderLocationScreenState extends State<RiderLocationScreen> {
  bool _notifyChecked = false;
  bool _notifyLoading = false;
  String? _notifyStatus;
  String? _cachedToken;

  @override
  void initState() {
    super.initState();
    // No token fetch on startup — only request permission when user opts in
  }

  Future<String?> _getToken() async {
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (mounted) {
          setState(
            () => _notifyStatus =
                'Notifications blocked. Click the 🔒 lock icon in the address bar → Notifications → Allow, then refresh.',
          );
        }
        return null;
      }
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return null;
      }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: _kVapidKey,
      );
      return token;
    } catch (e) {
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
        setState(() {
          _notifyStatus =
              'Notifications blocked. To enable: click the 🔒 lock icon in your browser address bar → Notifications → Allow, then refresh.';
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        '🛵 Rider Location',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Map
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    child: RiderLocationWidget(),
                  ),
                ),
              ),

              // Notify checkbox
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.blueGrey.shade200),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
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
                                  onChanged: (v) => _toggleNotify(v ?? false),
                                  activeColor: Colors.blueAccent,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                          const SizedBox(width: 6),
                          const Expanded(
                            child: Text(
                              'Notify me when rider is available',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.blueGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_notifyStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 4),
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
                    ],
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

// ===================== ADMIN PANEL =====================

class AdminRiderPanel extends StatefulWidget {
  const AdminRiderPanel({super.key});

  @override
  State<AdminRiderPanel> createState() => _AdminRiderPanelState();
}

class _AdminRiderPanelState extends State<AdminRiderPanel> {
  bool _sharing = false;
  bool _locating = false;
  bool _notified = false;
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleSharing(bool val) {
    setState(() {
      _sharing = val;
      _notified = false;
    });
    if (val) {
      _pushLocation(notify: true);
      _timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _pushLocation(notify: false),
      );
    } else {
      _timer?.cancel();
      FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc).delete();
    }
  }

  Future<void> _pushLocation({bool notify = false}) async {
    setState(() => _locating = true);
    try {
      final completer = Completer<(double, double)>();
      web.window.navigator.geolocation.getCurrentPosition(
        (web.GeolocationPosition pos) {
          completer.complete((pos.coords.latitude, pos.coords.longitude));
        }.toJS,
        (web.GeolocationPositionError err) {
          completer.completeError(err.message);
        }.toJS,
      );
      final (lat, lng) = await completer.future;
      await FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc).set({
        'lat': lat,
        'lng': lng,
        'updatedAt': Timestamp.now(),
      });

      // Send push only on first location share (when rider goes online)
      if (notify && !_notified) {
        await _notifyAllSubscribers();
        if (mounted) setState(() => _notified = true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Location error: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        '🛵 Rider Location Sharing',
        style: TextStyle(fontSize: 15),
      ),
      content: _buildPanel(),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.pop(context);
          },
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Switch(value: _sharing, onChanged: _toggleSharing),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _sharing ? 'Sharing location...' : 'Location sharing OFF',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _sharing ? Colors.green : Colors.blueGrey,
                ),
              ),
            ),
            if (_locating)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_sharing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'GPS updates every 15 seconds.\nCustomers can now see your location.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                if (_notified)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      '✅ Subscribers notified.',
                      style: TextStyle(fontSize: 12, color: Colors.green),
                    ),
                  ),
              ],
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
      ],
    );
  }
}
