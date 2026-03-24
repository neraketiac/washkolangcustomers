import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

@JS('navigator.wakeLock.request')
external JSPromise<JSObject> _requestWakeLock(JSString type);

const _kWatchers = 'rider_watchers';
const _kCollection = 'rider_location';
const _kDoc = 'current';
const _kSubCollection = 'push_subscriptions';
const _kVapidKey =
    'BFLfvLXFkeaA_h1fn-nEpGU9kMfIVpgZyEM5lmkiihEZ__sJYPT_yhRiyy6Ikm2x1tDJUgWPI7m78oQH235pxuo';
const _kPushServer = 'https://rider-push-server.onrender.com/send';

// Watcher is considered stale if lastSeen is older than this
const _kStaleThreshold = Duration(minutes: 2);

// ===================== NOTIFICATION HELPERS =====================

const _kPreviousTokenKey = 'fcm_token';

Future<void> _saveTokenToFirestore(String token) async {
  // Delete old token doc if device got a new token
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
  String? _facing; // 'left' or 'right'
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
      final facing = data['facing'] as String?;
      final ts = data['updatedAt'] as Timestamp?;

      if (mounted) {
        setState(() {
          _loading = false;
          _offline = !isOnline;
          if (lat != null) _lat = lat;
          if (lng != null) _lng = lng;
          if (facing != null) _facing = facing;
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
    if (_loading || _lat == null || _lng == null) {
      return const Center(child: CircularProgressIndicator());
    }

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
          child: _LeafletMap(
            key: const ValueKey('rider-map'),
            lat: _lat!,
            lng: _lng!,
            facing: _facing,
          ),
        ),
      ],
    );
  }
}

// ===================== LEAFLET MAP =====================

class _LeafletMap extends StatefulWidget {
  final double lat;
  final double lng;
  final String? facing;
  const _LeafletMap({
    super.key,
    required this.lat,
    required this.lng,
    this.facing,
  });

  @override
  State<_LeafletMap> createState() => _LeafletMapState();
}

class _LeafletMapState extends State<_LeafletMap> {
  late final String _viewId;
  late web.HTMLIFrameElement _iframe;
  bool _ready = false;
  double? _pendingLat;
  double? _pendingLng;
  String? _pendingFacing;

  @override
  void initState() {
    super.initState();
    _viewId = 'leaflet-map-${DateTime.now().millisecondsSinceEpoch}';

    final html = _buildLeafletHtml(widget.lat, widget.lng);
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
          // Always send current position + facing immediately on ready
          _sendUpdate(
            _pendingLat ?? widget.lat,
            _pendingLng ?? widget.lng,
            _pendingFacing ?? widget.facing,
          );
          _pendingLat = null;
          _pendingLng = null;
          _pendingFacing = null;
        }
      }.toJS,
    );

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (_) => _iframe);
  }

  void _sendUpdate(double lat, double lng, String? facing) {
    final data = <String, dynamic>{'lat': lat, 'lng': lng};
    if (facing != null) data['facing'] = facing;
    _iframe.contentWindow?.postMessage(data.jsify(), '*'.toJS);
  }

  void updatePosition(double lat, double lng, String? facing) {
    if (_ready) {
      _sendUpdate(lat, lng, facing);
    } else {
      _pendingLat = lat;
      _pendingLng = lng;
      _pendingFacing = facing;
    }
  }

  @override
  void didUpdateWidget(_LeafletMap old) {
    super.didUpdateWidget(old);
    if (old.lat != widget.lat ||
        old.lng != widget.lng ||
        old.facing != widget.facing) {
      updatePosition(widget.lat, widget.lng, widget.facing);
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewId);
  }

  static String _buildLeafletHtml(double lat, double lng) {
    return '''<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
html,body,#map{margin:0;padding:0;width:100%;height:100%;}
</style>
</head>
<body>
<div id="map"></div>
<script>
var map=L.map('map',{zoomControl:true,attributionControl:false}).setView([$lat,$lng],16);
L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png').addTo(map);
var facingRight=false;

function makeIcon(right){
  var flip=right?'scaleX(-1)':'scaleX(1)';
  return L.divIcon({
    html:'<div style="font-size:28px;line-height:1;display:inline-block;transform:'+flip+';">&#x1F6FA;</div>',
    iconSize:[36,36],iconAnchor:[18,18],className:''
  });
}

var marker=L.marker([$lat,$lng],{icon:makeIcon(false)}).addTo(map);

// Smooth animation state
var fromLat=$lat, fromLng=$lng;
var toLat=$lat, toLng=$lng;
var animStart=null, animDuration=800;
var rafId=null;

function animateTo(newLat,newLng){
  fromLat=currentLat(); fromLng=currentLng();
  toLat=newLat; toLng=newLng;
  animStart=null;
  if(rafId) cancelAnimationFrame(rafId);
  rafId=requestAnimationFrame(step);
}

function currentLat(){
  return marker.getLatLng().lat;
}
function currentLng(){
  return marker.getLatLng().lng;
}

function easeInOut(t){
  return t<0.5?2*t*t:1-Math.pow(-2*t+2,2)/2;
}

function step(ts){
  if(!animStart) animStart=ts;
  var t=Math.min((ts-animStart)/animDuration,1);
  var e=easeInOut(t);
  var lat=fromLat+(toLat-fromLat)*e;
  var lng=fromLng+(toLng-fromLng)*e;
  marker.setLatLng([lat,lng]);
  if(t<1){
    rafId=requestAnimationFrame(step);
  } else {
    rafId=null;
    map.panTo([toLat,toLng],{animate:true,duration:0.5,easeLinearity:0.5});
  }
}

window.parent.postMessage('leaflet-ready','*');

window.addEventListener('message',function(e){
  var d=e.data;
  if(d&&d.lat!==undefined&&d.lng!==undefined){
    if(d.facing!==undefined&&d.facing!==null){
      var right=(d.facing==='right');
      if(right!==facingRight){
        facingRight=right;
        marker.setIcon(makeIcon(facingRight));
      }
    }
    animateTo(d.lat,d.lng);
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
    String? publicIp;
    try {
      final resp = await http.get(
        Uri.parse('https://api.ipify.org?format=json'),
      );
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body);
        publicIp = json['ip'] as String?;
      }
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
  Timer? _cleanupTimer;
  int _watcherCount = 0;
  int _staleCount = 0;
  StreamSubscription? _watcherSub;
  JSObject? _wakeLock;
  double? _prevLng;

  Future<void> _acquireWakeLock() async {
    try {
      _wakeLock = await _requestWakeLock('screen'.toJS).toDart;
    } catch (_) {}
  }

  Future<void> _releaseWakeLock() async {
    try {
      _wakeLock?.callMethod('release'.toJS);
    } catch (_) {}
    _wakeLock = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cleanupTimer?.cancel();
    _watcherSub?.cancel();
    _releaseWakeLock();
    super.dispose();
  }

  void _startWatcherStream() {
    _watcherSub?.cancel();
    _watcherSub = FirebaseFirestore.instance
        .collection(_kWatchers)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final now = DateTime.now();
          int stale = 0;
          for (final doc in snap.docs) {
            final ts = doc.data()['lastSeen'];
            if (ts is Timestamp) {
              if (now.difference(ts.toDate()) > _kStaleThreshold) stale++;
            }
          }
          setState(() {
            _watcherCount = snap.docs.length;
            _staleCount = stale;
          });
        });
  }

  void _stopWatcherStream() {
    _watcherSub?.cancel();
    _watcherSub = null;
    if (mounted)
      setState(() {
        _watcherCount = 0;
        _staleCount = 0;
      });
  }

  Future<int> _cleanStaleWatchers() async {
    final snap = await FirebaseFirestore.instance.collection(_kWatchers).get();
    final now = DateTime.now();
    final batch = FirebaseFirestore.instance.batch();
    int removed = 0;
    for (final doc in snap.docs) {
      final ts = doc.data()['lastSeen'];
      if (ts is Timestamp) {
        if (now.difference(ts.toDate()) > _kStaleThreshold) {
          batch.delete(doc.reference);
          removed++;
        }
      }
    }
    if (removed > 0) await batch.commit();
    return removed;
  }

  void _toggleSharing(bool val) {
    setState(() {
      _sharing = val;
      _notified = false;
    });
    if (val) {
      _acquireWakeLock();
      _pushLocation(notify: true);
      _startWatcherStream();
      _timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _pushLocation(notify: false),
      );
      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _cleanStaleWatchers(),
      );
    } else {
      _timer?.cancel();
      _cleanupTimer?.cancel();
      _releaseWakeLock();
      _stopWatcherStream();
      _prevLng = null;
      FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc).update({
        'isOnline': false,
      });
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

      // Determine facing direction from longitude delta
      String? facing;
      if (_prevLng != null && lng != _prevLng) {
        facing = lng > _prevLng! ? 'right' : 'left';
      }
      _prevLng = lng;

      await FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc).set({
        'lat': lat,
        'lng': lng,
        if (facing != null) 'facing': facing,
        'updatedAt': Timestamp.now(),
        'isOnline': true,
      });

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
            _cleanupTimer?.cancel();
            _releaseWakeLock();
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
                    if (_staleCount > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '($_staleCount stale)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_staleCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton.icon(
                      onPressed: () async {
                        final removed = await _cleanStaleWatchers();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Removed $removed stale watcher(s).',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.cleaning_services, size: 14),
                      label: const Text(
                        'Clean stale watchers',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange,
                        padding: EdgeInsets.zero,
                      ),
                    ),
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
