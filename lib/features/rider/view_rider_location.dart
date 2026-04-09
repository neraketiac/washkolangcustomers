import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

const _kCollection = 'rider_location';
const _kDoc = 'current';

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
  bool _streamError = false;
  String? _lastUpdated;
  bool _showEta = false;
  List<Map<String, dynamic>> _routeStops = [];
  Timestamp? _routeUpdatedAt;
  StreamSubscription? _sub;
  StreamSubscription? _etaSub;

  // Customer ETA (fetched if card number known)
  DateTime? _myEta;
  int? _myEtaMinutes;
  double? _myLat;
  double? _myLng;

  List<String> _todaySlots = [];
  bool _loadingSlots = false;

  @override
  void initState() {
    super.initState();
    _openStream();
    _loadMyEta();
  }

  /// Listens live to the customer's loyalty doc for ETA updates.
  void _loadMyEta() {
    _etaSub?.cancel();
    try {
      final savedCode = web.window.localStorage.getItem('customer_code');
      if (savedCode == null) return;
      final cardNumber = int.tryParse(savedCode);
      if (cardNumber == null) return;

      _etaSub = FirebaseFirestore.instance
          .collection('loyalty')
          .where('cardNumber', isEqualTo: cardNumber)
          .limit(1)
          .snapshots()
          .listen((snap) {
            if (snap.docs.isEmpty || !mounted) return;
            final data = snap.docs.first.data();
            final etaTs = data['riderEta'] as Timestamp?;
            final etaMins = data['riderEtaMinutes'] as int?;
            final lat = (data['lat'] as num?)?.toDouble();
            final lng = (data['lng'] as num?)?.toDouble();
            setState(() {
              _myEta = etaTs?.toDate().toLocal();
              _myEtaMinutes = etaMins;
              _myLat = lat;
              _myLng = lng;
            });
          });
    } catch (_) {}
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
          .get()
          .timeout(const Duration(seconds: 10));
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
    _sub = ref.snapshots().listen(
      (snap) {
        if (!snap.exists) {
          if (mounted)
            setState(() {
              _loading = false;
              _offline = true;
              _streamError = false;
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
        final showEta = data['showEta'] as bool? ?? false;
        final rawStops = data['routeStops'];
        final routeUpdatedAt = data['routeUpdatedAt'] as Timestamp?;
        final routeStops = (rawStops is List)
            ? rawStops
                  .whereType<Map>()
                  .map(
                    (s) => {
                      'lat': (s['lat'] as num?)?.toDouble() ?? 0.0,
                      'lng': (s['lng'] as num?)?.toDouble() ?? 0.0,
                      'etaTime': s['etaTime'] as String? ?? '',
                    },
                  )
                  .where((s) => s['etaTime'] != '')
                  .toList()
            : <Map<String, dynamic>>[];
        final ts = data['updatedAt'] as Timestamp?;

        if (mounted) {
          setState(() {
            _loading = false;
            _streamError = false;
            _offline = !isOnline;
            if (lat != null) _lat = lat;
            if (lng != null) _lng = lng;
            if (facing != null) _facing = facing;
            _riderStatus = status;
            // Trigger ETA load when showEta transitions false→true
            if (showEta && !_showEta) _loadMyEta();
            _showEta = showEta;
            _routeStops = List<Map<String, dynamic>>.from(routeStops);
            _routeUpdatedAt = routeUpdatedAt;
            if (ts != null) {
              final d = ts.toDate().toLocal();
              _lastUpdated =
                  '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            }
          });
        }
        if (!isOnline) _loadTodaySlots();
      },
      onError: (e) {
        if (mounted)
          setState(() {
            _loading = false;
            _streamError = true;
          });
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _etaSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_streamError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 40, color: Colors.blueGrey),
              const SizedBox(height: 12),
              const Text(
                'Unable to connect. Please check your internet connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.blueGrey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _streamError = false;
                  });
                  _sub?.cancel();
                  _openStream();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
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
        // ETA banner — shown when rider enabled showEta and customer has ETA
        if (_showEta && _myEta != null && !_offline)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            color: Colors.teal.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.teal.shade700),
                const SizedBox(width: 6),
                Text(
                  'Rider arrives at ${_myEta!.hour.toString().padLeft(2, '0')}:${_myEta!.minute.toString().padLeft(2, '0')}'
                  '${_myEtaMinutes != null ? '  (~${_myEtaMinutes}min)' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.teal.shade800,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _LeafletMap(
            key: const ValueKey('rider-map'),
            lat: _lat!,
            lng: _lng!,
            facing: _facing,
            customerLat: (_showEta && _myLat != null) ? _myLat : null,
            customerLng: (_showEta && _myLng != null) ? _myLng : null,
            showRoute:
                _showEta && _myLat != null && _myLng != null && !_offline,
            routeStops: (_showEta && !_offline) ? _routeStops : const [],
            routeUpdatedAt: (_showEta && !_offline) ? _routeUpdatedAt : null,
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
  final double? customerLat;
  final double? customerLng;
  final bool showRoute;
  final List<Map<String, dynamic>> routeStops;
  final Timestamp? routeUpdatedAt;
  const _LeafletMap({
    super.key,
    required this.lat,
    required this.lng,
    this.facing,
    this.customerLat,
    this.customerLng,
    this.showRoute = false,
    this.routeStops = const [],
    this.routeUpdatedAt,
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
    if (widget.showRoute && widget.customerLat != null) {
      data['customerLat'] = widget.customerLat;
      data['customerLng'] = widget.customerLng;
      data['showRoute'] = true;
    }
    if (widget.routeStops.isNotEmpty) {
      data['routeStops'] = widget.routeStops;
    } else {
      data['routeStops'] = <Map<String, dynamic>>[];
    }
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
        old.facing != widget.facing ||
        old.showRoute != widget.showRoute ||
        old.customerLat != widget.customerLat ||
        old.routeUpdatedAt != widget.routeUpdatedAt) {
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

// Recenter control
var RecenterControl = L.Control.extend({
  options: { position: 'bottomright' },
  onAdd: function() {
    var btn = L.DomUtil.create('button','leaflet-bar leaflet-control');
    btn.innerHTML = '⊕';
    btn.title = 'Recenter on rider';
    btn.style.cssText = 'width:30px;height:30px;font-size:18px;line-height:28px;text-align:center;cursor:pointer;background:#fff;border:none;border-radius:4px;box-shadow:0 1px 5px rgba(0,0,0,0.4);';
    L.DomEvent.on(btn,'click',function(e){
      L.DomEvent.stopPropagation(e);
      map.setView(marker.getLatLng(),16,{animate:true});
    });
    return btn;
  }
});
new RecenterControl().addTo(map);

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
    if(d.recenter){
      map.setView([d.lat,d.lng],16);
      marker.setLatLng([d.lat,d.lng]);
      fromLat=d.lat; fromLng=d.lng; toLat=d.lat; toLng=d.lng;
    } else {
      animateTo(d.lat,d.lng);
      // Trim route after animation
      setTimeout(function(){ trimRouteFromRider(d.lat, d.lng); }, 850);
    }
    // Draw route to customer if requested
    if(d.showRoute && d.customerLat!==undefined){
      drawRoute(d.lat, d.lng, d.customerLat, d.customerLng);
    } else if(!d.showRoute) {
      // Clear personalized route
      if(routeLayer){ map.removeLayer(routeLayer); routeLayer=null; }
      if(customerMarker){ map.removeLayer(customerMarker); customerMarker=null; }
    }
    // Draw all route stops — empty array clears them
    if(d.routeStops!==undefined){
      drawStopMarkers(d.routeStops, d.lat, d.lng);
    }
  }
});

var customerMarker = null;
var routeLayer = null;
var fullRouteLayer = null;
var fullRouteCoords = []; // stored for trimming
var stopMarkers = [];

function clearStopMarkers(){
  stopMarkers.forEach(function(m){ map.removeLayer(m); });
  stopMarkers = [];
  if(fullRouteLayer){ map.removeLayer(fullRouteLayer); fullRouteLayer=null; }
  fullRouteCoords = [];
  if(window._labelInterval){ clearInterval(window._labelInterval); window._labelInterval=null; }
  window._lastStops = null;
}

// Find closest point index in fullRouteCoords to (lat,lng)
function closestPointIndex(lat, lng){
  var best=0, bestDist=Infinity;
  for(var i=0;i<fullRouteCoords.length;i++){
    var c=fullRouteCoords[i];
    var d=(c[0]-lat)*(c[0]-lat)+(c[1]-lng)*(c[1]-lng);
    if(d<bestDist){bestDist=d;best=i;}
  }
  return best;
}

// Trim displayed route to show only from rider's current position forward
function trimRouteFromRider(lat, lng){
  if(fullRouteCoords.length===0) return;
  var idx=closestPointIndex(lat,lng);
  var remaining=fullRouteCoords.slice(idx);
  if(remaining.length<2){
    if(fullRouteLayer){map.removeLayer(fullRouteLayer);fullRouteLayer=null;}
    return;
  }
  if(fullRouteLayer) map.removeLayer(fullRouteLayer);
  fullRouteLayer=L.polyline(remaining,{color:'#00897b',weight:3,opacity:0.7,dashArray:'8,5'}).addTo(map);
}

async function drawStopMarkers(stops, riderLat, riderLng){
  clearStopMarkers();
  if(!stops || stops.length === 0) return;

  window._lastStops = stops;

  function renderLabels(){
    stopMarkers.forEach(function(m){ map.removeLayer(m); });
    stopMarkers = [];
    stops.forEach(function(s){
      if(!s.lat || !s.lng || !s.etaTime) return;
      var parts = s.etaTime.split(':');
      var now = new Date();
      var eta = new Date(now.getFullYear(), now.getMonth(), now.getDate(), parseInt(parts[0]), parseInt(parts[1]), 0);
      var diffMs = eta - now;
      var diffMin = Math.round(diffMs / 60000);
      var label = diffMin <= 0 ? 'Arriving' : diffMin + ' min';
      var icon = L.divIcon({
        html:'<div style="background:#1b5e20;color:#fff;border-radius:10px;padding:3px 8px;font-size:12px;font-weight:bold;white-space:nowrap;box-shadow:0 2px 6px rgba(0,0,0,0.6);text-shadow:-1px -1px 0 #000,1px -1px 0 #000,-1px 1px 0 #000,1px 1px 0 #000;border:1.5px solid #fff;">'+label+'</div>',
        iconAnchor:[24,12],className:''
      });
      var m = L.marker([s.lat,s.lng],{icon:icon}).addTo(map);
      stopMarkers.push(m);
    });
  }

  renderLabels();

  if(window._labelInterval) clearInterval(window._labelInterval);
  window._labelInterval = setInterval(function(){
    if(window._lastStops && window._lastStops.length > 0) renderLabels();
  }, 60000);

  // Draw full route: rider → all stops, store coords for trimming
  if(riderLat===undefined || riderLng===undefined) return;
  var validStops = stops.filter(function(s){ return s.lat && s.lng; });
  if(validStops.length === 0) return;
  var coords = riderLng+','+riderLat+';'+validStops.map(function(s){ return s.lng+','+s.lat; }).join(';');
  try {
    var url='https://router.project-osrm.org/route/v1/driving/'+coords+'?overview=full&geometries=geojson&steps=false';
    var resp=await fetch(url);
    var data=await resp.json();
    if(data.routes&&data.routes.length>0){
      // Store full coords for trimming — [lat,lng] pairs
      fullRouteCoords = data.routes[0].geometry.coordinates.map(function(c){return[c[1],c[0]];});
      fullRouteLayer=L.polyline(fullRouteCoords,{color:'#00897b',weight:3,opacity:0.7,dashArray:'8,5'}).addTo(map);
    }
  } catch(err){
    var latlngs=[[riderLat,riderLng]].concat(validStops.map(function(s){return[s.lat,s.lng];}));
    fullRouteCoords = latlngs;
    fullRouteLayer=L.polyline(latlngs,{color:'#00897b',weight:2,dashArray:'8,5',opacity:0.6}).addTo(map);
  }
}

async function drawRoute(rLat, rLng, cLat, cLng){
  if(!customerMarker){
    var homeIcon = L.divIcon({
      html:'<div style="font-size:22px;line-height:1;">📍</div>',
      iconSize:[28,28],iconAnchor:[14,28],className:''
    });
    customerMarker = L.marker([cLat,cLng],{icon:homeIcon}).addTo(map);
  } else {
    customerMarker.setLatLng([cLat,cLng]);
  }
  if(routeLayer){ map.removeLayer(routeLayer); routeLayer=null; }
  try {
    var url='https://router.project-osrm.org/route/v1/driving/'+rLng+','+rLat+';'+cLng+','+cLat+'?overview=full&geometries=geojson';
    var resp=await fetch(url);
    var data=await resp.json();
    if(data.routes&&data.routes.length>0){
      routeLayer=L.geoJSON(data.routes[0].geometry,{
        style:{color:'#00897b',weight:4,opacity:0.85,dashArray:'8,6'}
      }).addTo(map);
    }
  } catch(err){
    routeLayer=L.polyline([[rLat,rLng],[cLat,cLng]],{color:'#00897b',weight:3,dashArray:'8,6',opacity:0.7}).addTo(map);
  }
}
</script>
</body>
</html>''';
  }
}

// ===================== RIDER LOCATION SCREEN =====================
