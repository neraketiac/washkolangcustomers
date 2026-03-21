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

class _RiderLocationWidgetState extends State<RiderLocationWidget> {
  double? _lat;
  double? _lng;
  bool _loading = true;
  String? _lastUpdated;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = FirebaseFirestore.instance
        .collection(_kCollection)
        .doc(_kDoc)
        .snapshots()
        .listen((snap) {
          if (!snap.exists) {
            setState(() => _loading = false);
            return;
          }
          final data = snap.data()!;
          final ts = data['updatedAt'] as Timestamp?;
          setState(() {
            _lat = (data['lat'] as num?)?.toDouble();
            _lng = (data['lng'] as num?)?.toDouble();
            _loading = false;
            if (ts != null) {
              final d = ts.toDate().toLocal();
              _lastUpdated =
                  '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
            }
          });
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
    if (_lat == null || _lng == null) {
      return const Center(
        child: Text(
          'Rider location not available yet.\nCheck back later.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.blueGrey, fontSize: 13),
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
          'https://maps.google.com/maps?q=${widget.lat},${widget.lng}&z=16&output=embed'
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

class RiderLocationScreen extends StatelessWidget {
  const RiderLocationScreen({super.key});

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
              // map fills all remaining screen space
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(10, 0, 10, 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                    child: RiderLocationWidget(),
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
  String? _error;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleSharing(bool val) {
    setState(() => _sharing = val);
    if (val) {
      _pushLocation();
      _timer = Timer.periodic(
        const Duration(seconds: 15),
        (_) => _pushLocation(),
      );
    } else {
      _timer?.cancel();
      FirebaseFirestore.instance.collection(_kCollection).doc(_kDoc).delete();
    }
  }

  Future<void> _pushLocation() async {
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
        '� Rider Location Sharing',
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
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'GPS updates every 15 seconds.\nCustomers can now see your location.',
              style: TextStyle(fontSize: 12, color: Colors.blueGrey),
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
