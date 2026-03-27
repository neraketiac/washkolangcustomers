import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _kCollection = 'rider_location';
const _kDoc = 'current';
const _kSubCollection = 'push_subscriptions';
const _kVapidKey =
    'BFLfvLXFkeaA_h1fn-nEpGU9kMfIVpgZyEM5lmkiihEZ__sJYPT_yhRiyy6Ikm2x1tDJUgWPI7m78oQH235pxuo';

// ===================== NOTIFICATION HELPERS =====================

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
  String? _facing;
  String? _riderStatus;
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
        final enabled = data[entry.key] == true;
        final endHour = _scheduleSlotEndHour[entry.key] ?? 0;
        if (enabled && now.hour < endHour) slots.add(entry.value);
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
      final status = data['status'] as String?;
      final ts = data['updatedAt'] as Timestamp?;

      if (mounted) {
        setState(() {
          _loading = false;
          _offline = !isOnline;
          if (lat != null) _lat = lat;
          if (lng != null) _lng = lng;
          if (facing != null) _facing = facing;
          _riderStatus = status;
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
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lat == null || _lng == null) {
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
        if (_riderStatus != null && !_offline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 5),
            color: Colors.blue.shade50,
            child: Text(
              _riderStatus!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade800,
              ),
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

function currentLat(){ return marker.getLatLng().lat; }
function currentLng(){ return marker.getLatLng().lng; }

function easeInOut(t){
  return t<0.5?2*t*t:1-Math.pow(-2*t+2,2)/2;
}

function step(ts){
  if(!animStart) animStart=ts;
  var t=Math.min((ts-animStart)/animDuration,1);
  var e=easeInOut(t);
  marker.setLatLng([fromLat+(toLat-fromLat)*e, fromLng+(toLng-fromLng)*e]);
  if(t<1){ rafId=requestAnimationFrame(step); }
  else { rafId=null; map.panTo([toLat,toLng],{animate:true,duration:0.5,easeLinearity:0.5}); }
}

window.parent.postMessage('leaflet-ready','*');

window.addEventListener('message',function(e){
  var d=e.data;
  if(d&&d.lat!==undefined&&d.lng!==undefined){
    if(d.facing!==undefined&&d.facing!==null){
      var right=(d.facing==='right');
      if(right!==facingRight){ facingRight=right; marker.setIcon(makeIcon(facingRight)); }
    }
    animateTo(d.lat,d.lng);
  }
});
</script>
</body>
</html>''';
  }
}

// ===================== RIDER LOCATION SCREEN =====================

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreNotifyState());
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
        if (val) {
          setState(() {
            _notifyStatus =
                'Notifications blocked. To enable: click the lock icon in your browser address bar, then Notifications, then Allow, then refresh.';
            _notifyChecked = false;
          });
        }
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
                              'Notify me when rider is online',
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
