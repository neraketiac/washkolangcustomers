import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

const _kWatchers = 'rider_watchers';
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

  await http.post(
    Uri.parse(_kPushServer),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'tokens': tokens,
      'title': 'Rider is Available!',
      'body': 'Your rider is now online and sharing location.',
      'url': 'https://washkolang.online',
    }),
  );
}

// ===================== INLINE MAP WIDGET =====================

class RiderLocationWidget extends StatefulWidget {
  const RiderLocationWidget({super.key});

  @override
  State<RiderLocationWidget> createState() => _RiderLocationWidgetState();
}

// slot key -> display label
const _scheduleSlotLabels = {
  'slot7to9': '7am-9am',
  'slot9to10': '9am-10am',
  'slot10to12': '10am-12pm',
  'slot1to3': '1pm-3pm',
  'slot3to5': '3pm-5pm',
  'slot5to7': '5pm-7pm',
  'slot7to9pm': '7pm-9pm',
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
  double? _heading;
  bool _loading = true;
  bool _offline = false;
  String? _lastUpdated;
  StreamSubscription? _sub;

  List<String> _todaySlots = [];
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _openStream();
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
        if (enabled && now.hour < endHour) slots.add(label);
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

  void _openStream() {
    final ref = FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc);
    _sub = ref.snapshots().listen((snap) {
      if (!snap.exists) {
        if (mounted)
          setState(() {
            _loading = false;
            _offline = true;
          });
        _loadTodaySlots();
        return;
      }
      final data = snap.data()!;
      final isOnline = data['isOnline'] as bool? ?? true;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final heading = (data['heading'] as num?)?.toDouble();
      final ts = data['updatedAt'] as Timestamp?;

      if (mounted) {
        setState(() {
          _loading = false;
          _offline = !isOnline;
          if (lat != null) _lat = lat;
          if (lng != null) _lng = lng;
          if (heading != null) _heading = heading;
          if (ts != null) {
            final d = ts.toDate().toLocal();
            _lastUpdated =
                '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
          }
        });
      }
      if (!isOnline) _loadTodaySlots();
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

    if (_offline && (_lat == null || _lng == null)) {
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
        if (_offline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: Colors.orange.shade100,
            child: const Text(
              'Rider stopped sharing - showing last known location',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.deepOrange),
            ),
          )
        else if (_lastUpdated != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Last updated: $_lastUpdated',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
          ),
        Expanded(
          child: _LeafletMap(lat: _lat!, lng: _lng!, heading: _heading),
        ),
      ],
    );
  }
}

// ===================== LEAFLET MAP =====================

class _LeafletMap extends StatefulWidget {
  final double lat;
  final double lng;
  final double? heading;
  const _LeafletMap({required this.lat, required this.lng, this.heading});

  @override
  State<_LeafletMap> createState() => _LeafletMapState();
}

class _LeafletMapState extends State<_LeafletMap> {
  late final String _viewId;
  late web.HTMLIFrameElement _iframe;
  bool _ready = false;
  double? _pendingLat;
  double? _pendingLng;
  double? _pendingHeading;

  @override
  void initState() {
    super.initState();
    _viewId = 'leaflet-map-${DateTime.now().millisecondsSinceEpoch}';

    final html = _buildLeafletHtml(widget.lat, widget.lng, widget.heading);
    final blob = web.Blob(
      [html.toJS].toJS,
      web.BlobPropertyBag(type: 'text/html'),
    );
    final url = web.URL.createObjectURL(blob);

    _iframe = web.HTMLIFrameElement()
      ..src = url
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allowFullscreen = true;

    web.window.addEventListener(
      'message',
      (web.Event e) {
        final msg = e as web.MessageEvent;
        if (msg.data.dartify() == 'leaflet-ready') {
          _ready = true;
          if (_pendingLat != null && _pendingLng != null) {
            _sendUpdate(_pendingLat!, _pendingLng!, _pendingHeading);
            _pendingLat = null;
            _pendingLng = null;
            _pendingHeading = null;
          }
        }
      }.toJS,
    );

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) => _iframe);
  }

  void _sendUpdate(double lat, double lng, double? heading) {
    final data = <String, dynamic>{'lat': lat, 'lng': lng};
    if (heading != null) data['heading'] = heading;
    _iframe.contentWindow?.postMessage(data.jsify(), '*'.toJS);
  }

  void updatePosition(double lat, double lng, double? heading) {
    if (_ready) {
      _sendUpdate(lat, lng, heading);
    } else {
      _pendingLat = lat;
      _pendingLng = lng;
      _pendingHeading = heading;
    }
  }

  @override
  void didUpdateWidget(_LeafletMap old) {
    super.didUpdateWidget(old);
    if (old.lat != widget.lat ||
        old.lng != widget.lng ||
        old.heading != widget.heading) {
      updatePosition(widget.lat, widget.lng, widget.heading);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }

  static String _buildLeafletHtml(double lat, double lng, double? heading) {
    // Default facing right; flip left if heading is 180-360 (westward)
    final initialRight = (heading == null || (heading >= 0 && heading < 180));
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
html,body,#map{margin:0;padding:0;width:100%;height:100%;}
.leaflet-marker-icon{transition:left 0.8s ease,top 0.8s ease !important;}
</style>
</head>
<body>
<div id="map"></div>
<script>
var map=L.map('map',{zoomControl:true,attributionControl:false}).setView([$lat,$lng],16);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
var facingRight=$initialRight;
function makeIcon(right){
  var flip=right?'scaleX(1)':'scaleX(-1)';
  return L.divIcon({
    html:'<div style="font-size:28px;line-height:1;display:inline-block;transform:'+flip+';">&#x1F6F5;</div>',
    iconSize:[36,36],iconAnchor:[18,18],className:''
  });
}
var marker=L.marker([$lat,$lng],{icon:makeIcon(facingRight)}).addTo(map);
window.parent.postMessage('leaflet-ready','*');
window.addEventListener('message',function(e){
  var d=e.data;
  if(d&&d.lat!==undefined&&d.lng!==undefined){
    if(d.heading!==undefined&&d.heading!==null){
      var right=(d.heading>=0&&d.heading<180);
      if(right!==facingRight){facingRight=right;marker.setIcon(makeIcon(facingRight));}
    }
    var ll=L.latLng(d.lat,d.lng);
    marker.setLatLng(ll);
    map.panTo(ll,{animate:true,duration:0.8});
  }
});
</script>
</body>
</html>''';
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreNotifyState());
  }

  Future<void> _registerWatcher() async {
    await FirebaseFirestore.instance.collection(_kWatchers).doc(_sessionId).set(
      {'joinedAt': Timestamp.now(), 'lastSeen': Timestamp.now()},
    );
  }

  Future<void> _updateLastSeen() async {
    try {
      await FirebaseFirestore.instance
          .collection(_kWatchers)
          .doc(_sessionId)
          .update({'lastSeen': Timestamp.now()});
    } catch (_) {}
  }

  Future<void> _restoreNotifyState() async {
    try {
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

  @override
  void dispose() {
    _watcherTimer?.cancel();
    FirebaseFirestore.instance.collection(_kWatchers).doc(_sessionId).delete();
    super.dispose();
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
                'Notifications blocked. Click the lock icon in the address bar, then Notifications, then Allow, then refresh.',
          );
        }
        return null;
      }
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        return null;
      }
      return await FirebaseMessaging.instance.getToken(vapidKey: _kVapidKey);
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
                        'Rider Location',
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
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    child: RiderLocationWidget(),
                  ),
                ),
              ),
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
  int _watcherCount = 0;
  StreamSubscription? _watcherSub;

  @override
  void dispose() {
    _timer?.cancel();
    _watcherSub?.cancel();
    super.dispose();
  }

  void _startWatcherStream() {
    _watcherSub?.cancel();
    _watcherSub = FirebaseFirestore.instance
        .collection(_kWatchers)
        .snapshots()
        .listen((snap) {
          if (mounted) setState(() => _watcherCount = snap.docs.length);
        });
  }

  void _stopWatcherStream() {
    _watcherSub?.cancel();
    _watcherSub = null;
    if (mounted) setState(() => _watcherCount = 0);
  }

  void _toggleSharing(bool val) {
    setState(() {
      _sharing = val;
      _notified = false;
    });
    if (val) {
      _pushLocation(notify: true);
      _startWatcherStream();
      _timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _pushLocation(notify: false),
      );
    } else {
      _timer?.cancel();
      _stopWatcherStream();
      FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc).update({
        'isOnline': false,
      });
    }
  }

  Future<void> _pushLocation({bool notify = false}) async {
    setState(() => _locating = true);
    try {
      final completer = Completer<(double, double, double?)>();
      web.window.navigator.geolocation.getCurrentPosition(
        (web.GeolocationPosition pos) {
          final h = pos.coords.heading;
          final heading = (h != null && !h.isNaN) ? h.toDouble() : null;
          completer.complete((
            pos.coords.latitude,
            pos.coords.longitude,
            heading,
          ));
        }.toJS,
        (web.GeolocationPositionError err) {
          completer.completeError(err.message);
        }.toJS,
      );
      final (lat, lng, heading) = await completer.future;
      final data = <String, dynamic>{
        'lat': lat,
        'lng': lng,
        'updatedAt': Timestamp.now(),
        'isOnline': true,
      };
      if (heading != null) data['heading'] = heading;
      await FirebaseFirestore.instance
          .collection(_kCollection)
          .doc(_kDoc)
          .set(data);

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
        'Rider Location Sharing',
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
                  'GPS updates every 5 seconds.\nCustomers can now see your location.',
                  style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.remove_red_eye,
                      size: 15,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$_watcherCount ${_watcherCount == 1 ? 'customer' : 'customers'} watching',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (_notified)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'Subscribers notified.',
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
