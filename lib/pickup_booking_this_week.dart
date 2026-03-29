import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:washkolangcustomer/model/loyalty_order_online_model.dart';
import 'package:washkolangcustomer/model/model_rider_availability.dart';

// slot key → display label
const _wSlotLabels = {
  'slot7to9': '7am-9am',
  'slot9to10': '9am-10am',
  'slot10to12': '10am-12pm',
  'slot1to3': '1pm-3pm',
  'slot3to5': '3pm-5pm',
  'slot5to7': '5pm-7pm',
  'slot7to9pm': '7pm-9pm',
};

const _wSlotEndHour = {
  'slot7to9': 9,
  'slot9to10': 10,
  'slot10to12': 12,
  'slot1to3': 15,
  'slot3to5': 17,
  'slot5to7': 19,
  'slot7to9pm': 21,
};

bool _wIsSlotPast(DateTime date, String slotKey) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day.isBefore(today)) return true;
  if (day.isAfter(today)) return false;
  return now.hour >= (_wSlotEndHour[slotKey] ?? 0);
}

/// Returns the Sunday of the week containing [date].
DateTime _weekStart(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  // Dart: Mon=1..Sun=7, so Sun offset = (weekday % 7)
  return d.subtract(Duration(days: d.weekday % 7));
}

class PickupBookingThisWeekScreen extends StatefulWidget {
  final String? prefillName;
  final String? prefillContact;
  final String? prefillAddress;
  final bool requireAddress;
  final int cardNumber;

  const PickupBookingThisWeekScreen({
    super.key,
    this.prefillName,
    this.prefillContact,
    this.prefillAddress,
    this.requireAddress = true,
    this.cardNumber = 0,
  });

  @override
  State<PickupBookingThisWeekScreen> createState() =>
      _PickupBookingThisWeekScreenState();
}

class _PickupBookingThisWeekScreenState
    extends State<PickupBookingThisWeekScreen> {
  late DateTime _focusedWeekStart;
  late final DateTime _thisWeekStart; // never go before this
  DateTime? _selectedDate;
  ModelRiderAvailability? _selectedAvailability;
  String? _selectedSlot;
  bool _loadingAvailability = false;
  final Map<String, ModelRiderAvailability> _availabilityCache = {};

  late String _step;

  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _remarksController = TextEditingController();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _thisWeekStart = _weekStart(DateTime.now());
    _focusedWeekStart = _thisWeekStart;
    _step = widget.cardNumber > 0 ? 'bookings' : 'calendar';
    _nameController.text = widget.prefillName ?? '';
    _contactController.text = widget.prefillContact ?? '';
    _addressController.text = widget.prefillAddress ?? '';
    _loadWeekAvailability(_focusedWeekStart);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  String _docId(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadWeekAvailability(DateTime weekStart) async {
    setState(() => _loadingAvailability = true);
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final missing = days
        .where((d) => !_availabilityCache.containsKey(_docId(d)))
        .toList();
    if (missing.isNotEmpty) {
      final start = missing.first;
      final end = missing.last;
      final snap = await FirebaseFirestore.instance
          .collection('Rider_schedule')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();
      for (final doc in snap.docs) {
        final avail = ModelRiderAvailability.fromMap(doc.data());
        _availabilityCache[avail.docId] = avail;
      }
    }
    setState(() => _loadingAvailability = false);
  }

  ModelRiderAvailability? _availabilityFor(DateTime d) =>
      _availabilityCache[_docId(d)];

  void _prevWeek() {
    final prev = _focusedWeekStart.subtract(const Duration(days: 7));
    if (prev.isBefore(_thisWeekStart)) return; // block past weeks
    setState(() {
      _focusedWeekStart = prev;
      _selectedDate = null;
      _selectedAvailability = null;
      _selectedSlot = null;
    });
    _loadWeekAvailability(prev);
  }

  void _nextWeek() {
    final next = _focusedWeekStart.add(const Duration(days: 7));
    setState(() {
      _focusedWeekStart = next;
      _selectedDate = null;
      _selectedAvailability = null;
      _selectedSlot = null;
    });
    _loadWeekAvailability(next);
  }

  void _onDayTap(DateTime day) {
    final avail = _availabilityFor(day);
    if (avail == null) return;
    final hasActive = _wSlotLabels.keys.any((key) {
      return _slotValue(avail, key) && !_wIsSlotPast(day, key);
    });
    if (!hasActive) return;
    setState(() {
      _selectedDate = day;
      _selectedAvailability = avail;
      _selectedSlot = null;
    });
  }

  bool _slotValue(ModelRiderAvailability avail, String key) {
    switch (key) {
      case 'slot7to9':
        return avail.slot7to9;
      case 'slot9to10':
        return avail.slot9to10;
      case 'slot10to12':
        return avail.slot10to12;
      case 'slot1to3':
        return avail.slot1to3;
      case 'slot3to5':
        return avail.slot3to5;
      case 'slot5to7':
        return avail.slot5to7;
      case 'slot7to9pm':
        return avail.slot7to9pm;
      default:
        return false;
    }
  }

  String _monthName(int m) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][m];

  String _formatDate(DateTime d) =>
      '${_monthName(d.month)} ${d.day}, ${d.year}';

  String _weekRangeLabel() {
    final end = _focusedWeekStart.add(const Duration(days: 6));
    if (_focusedWeekStart.month == end.month) {
      return '${_monthName(_focusedWeekStart.month)} ${_focusedWeekStart.day}–${end.day}, ${end.year}';
    }
    return '${_monthName(_focusedWeekStart.month)} ${_focusedWeekStart.day} – ${_monthName(end.month)} ${end.day}, ${end.year}';
  }

  Future<void> _saveOrder() async {
    final name = _nameController.text.trim();
    final address = _addressController.text.trim();
    if (name.isEmpty || (widget.requireAddress && address.isEmpty)) {
      setState(
        () => _saveError = widget.requireAddress
            ? 'Name and Address are required'
            : 'Name is required',
      );
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      final docId = _docId(_selectedDate!);
      final freshDoc = await FirebaseFirestore.instance
          .collection('Rider_schedule')
          .doc(docId)
          .get();
      if (!freshDoc.exists) {
        setState(() {
          _saving = false;
          _saveError =
              'This schedule is no longer available. Please go back and select another date.';
        });
        return;
      }
      final freshAvail = ModelRiderAvailability.fromMap(freshDoc.data()!);
      _availabilityCache[docId] = freshAvail;
      final slotKey = _wSlotLabels.entries
          .firstWhere(
            (e) => e.value == _selectedSlot,
            orElse: () => const MapEntry('', ''),
          )
          .key;
      if (slotKey.isEmpty || !_slotValue(freshAvail, slotKey)) {
        setState(() {
          _saving = false;
          _selectedSlot = null;
          _selectedAvailability = freshAvail;
          _saveError =
              'Sorry, the "$_selectedSlot" slot is no longer available. Please select another time slot.';
        });
        return;
      }
      if (_wIsSlotPast(_selectedDate!, slotKey)) {
        setState(() {
          _saving = false;
          _saveError =
              'This time slot has already passed. Please select another.';
        });
        return;
      }
    } catch (e) {
      setState(() {
        _saving = false;
        _saveError = 'Could not verify schedule. Please try again.';
      });
      return;
    }

    final order = LoyaltyOrderOnlineModel(
      name: name,
      contact: _contactController.text.trim(),
      address: _addressController.text.trim(),
      remarks: _remarksController.text.trim(),
      scheduleDate: _selectedDate!,
      timeSlot: _selectedSlot!,
      createdAt: Timestamp.now(),
      cardNumber: widget.cardNumber,
    );
    await FirebaseFirestore.instance
        .collection('loyalty_order_online')
        .add(order.toMap());
    if (!mounted) return;
    setState(() => _saving = false);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Booking Confirmed!'),
        content: Text(
          'Pickup scheduled on ${_formatDate(_selectedDate!)} at $_selectedSlot.\n\nWe\'ll be in touch soon!',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.cardNumber > 0) {
                setState(() {
                  _step = 'bookings';
                  _selectedDate = null;
                  _selectedAvailability = null;
                  _selectedSlot = null;
                });
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
          child: _step == 'bookings'
              ? _buildBookingsStep()
              : _step == 'calendar'
              ? _buildCalendarStep()
              : _buildFormStep(),
        ),
      ),
    );
  }

  // ===================== BOOKINGS STEP =====================

  Widget _buildBookingsStep() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text(
                  'My Pickup Bookings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _selectedDate = null;
                  _selectedAvailability = null;
                  _selectedSlot = null;
                  _step = 'calendar';
                }),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('loyalty_order_online')
                .where('cardNumber', isEqualTo: widget.cardNumber)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_shipping_outlined,
                        size: 48,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No bookings yet.',
                        style: TextStyle(color: Colors.blueGrey, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => setState(() => _step = 'calendar'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Book a Pickup',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final orders =
                  snapshot.data!.docs
                      .map((d) => LoyaltyOrderOnlineModel.fromFirestore(d))
                      .toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              return ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                itemCount: orders.length,
                itemBuilder: (_, i) => _bookingCard(orders[i]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _bookingCard(LoyaltyOrderOnlineModel o) {
    final statusColor = switch (o.pickupStatus) {
      PickupStatus.queued => Colors.orange,
      PickupStatus.enroute => Colors.blue,
      PickupStatus.done => Colors.green,
    };
    final date =
        '${_monthName(o.scheduleDate.month)} ${o.scheduleDate.day}, ${o.scheduleDate.year}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.blue.shade100, blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.calendar_today,
                size: 14,
                color: Colors.blueGrey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$date · ${o.timeSlot}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  o.pickupStatus.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (o.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    o.address,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (o.remarks.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Note: ${o.remarks}',
              style: TextStyle(fontSize: 11, color: Colors.blueGrey.shade400),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  // ===================== CALENDAR STEP (week view) =====================

  Widget _buildCalendarStep() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekDays = List.generate(
      7,
      (i) => _focusedWeekStart.add(Duration(days: i)),
    );
    final isPrevDisabled = _focusedWeekStart.isAtSameMomentAs(_thisWeekStart);
    const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Column(
      children: [
        // top bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () {
                  if (widget.cardNumber > 0) {
                    setState(() => _step = 'bookings');
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
              const Expanded(
                child: Text(
                  'Schedule Pickup',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
        ),

        // week nav
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: isPrevDisabled ? null : _prevWeek,
                icon: Icon(
                  Icons.chevron_left,
                  color: isPrevDisabled
                      ? Colors.grey.shade300
                      : Colors.blueGrey,
                ),
              ),
              Text(
                _weekRangeLabel(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.blueGrey,
                ),
              ),
              IconButton(
                onPressed: _nextWeek,
                icon: const Icon(Icons.chevron_right, color: Colors.blueGrey),
              ),
            ],
          ),
        ),

        // day-of-week header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: dayNames
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),

        const SizedBox(height: 4),

        if (_loadingAvailability)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  // single row of 7 days
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: weekDays.map((date) {
                      final isPast = date.isBefore(today);
                      final avail = _availabilityFor(date);
                      final hasSlot =
                          avail != null &&
                          _wSlotLabels.keys.any(
                            (key) =>
                                _slotValue(avail, key) &&
                                !_wIsSlotPast(date, key),
                          );
                      final isSelected =
                          _selectedDate != null &&
                          _selectedDate!.year == date.year &&
                          _selectedDate!.month == date.month &&
                          _selectedDate!.day == date.day;
                      final isToday = date == today;

                      return Expanded(
                        child: GestureDetector(
                          onTap: (!isPast && hasSlot)
                              ? () => _onDayTap(date)
                              : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.all(2),
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1E88E5)
                                  : hasSlot && !isPast
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: isToday
                                  ? Border.all(
                                      color: const Color(0xFF1E88E5),
                                      width: 1.5,
                                    )
                                  : isSelected
                                  ? null
                                  : hasSlot && !isPast
                                  ? Border.all(
                                      color: Colors.blue.shade200,
                                      width: 1,
                                    )
                                  : null,
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.blueAccent.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Colors.white
                                        : isPast
                                        ? Colors.grey.shade400
                                        : hasSlot
                                        ? Colors.blue.shade900
                                        : Colors.blueGrey.shade300,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                if (!isPast && avail != null)
                                  ..._slotBadges(avail, isSelected),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  // legend
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _legendItem(const Color(0xFF43A047), '7am-9am'),
                      _legendItem(const Color(0xFF00ACC1), '9am-10am'),
                      _legendItem(const Color(0xFF1E88E5), '10am-12pm'),
                      _legendItem(const Color(0xFFFB8C00), '1pm-3pm'),
                      _legendItem(const Color(0xFFE53935), '3pm-5pm'),
                      _legendItem(const Color(0xFF8E24AA), '5pm-7pm'),
                      _legendItem(const Color(0xFF3949AB), '7pm-9pm'),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // slot picker
                  if (_selectedAvailability != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.shade100,
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_formatDate(_selectedDate!)} — pick a slot',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blueGrey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _buildSlotChips(_selectedAvailability!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // next button
                  if (_selectedDate != null && _selectedSlot != null)
                    GestureDetector(
                      onTap: () => setState(() => _step = 'form'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)],
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.5),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: const Text(
                          'Next →',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
      ],
    );
  }

  List<Widget> _slotBadges(ModelRiderAvailability avail, bool isSelected) {
    final slotColors = {
      'slot7to9': const Color(0xFF43A047),
      'slot9to10': const Color(0xFF00ACC1),
      'slot10to12': const Color(0xFF1E88E5),
      'slot1to3': const Color(0xFFFB8C00),
      'slot3to5': const Color(0xFFE53935),
      'slot5to7': const Color(0xFF8E24AA),
      'slot7to9pm': const Color(0xFF3949AB),
    };
    final active = <Color>[];
    for (final key in _wSlotLabels.keys) {
      if (_slotValue(avail, key) && !_wIsSlotPast(avail.date, key)) {
        active.add(slotColors[key]!);
      }
    }
    if (active.isEmpty) return [];
    return [
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 2,
        children: active
            .map(
              (c) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? Colors.white.withValues(alpha: 0.85) : c,
                ),
              ),
            )
            .toList(),
      ),
    ];
  }

  List<Widget> _buildSlotChips(ModelRiderAvailability avail) {
    final colors = {
      'slot7to9': const Color(0xFF43A047),
      'slot9to10': const Color(0xFF00ACC1),
      'slot10to12': const Color(0xFF1E88E5),
      'slot1to3': const Color(0xFFFB8C00),
      'slot3to5': const Color(0xFFE53935),
      'slot5to7': const Color(0xFF8E24AA),
      'slot7to9pm': const Color(0xFF3949AB),
    };
    return _wSlotLabels.entries.map((e) {
      final key = e.key;
      final label = e.value;
      final enabled = _slotValue(avail, key);
      if (!enabled) return const SizedBox.shrink();
      final isPast = _wIsSlotPast(_selectedDate!, key);
      final color = colors[key]!;
      final isSelected = _selectedSlot == label;
      return GestureDetector(
        onTap: isPast ? null : () => setState(() => _selectedSlot = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isPast
                ? Colors.grey.shade200
                : isSelected
                ? color
                : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isPast ? Colors.grey.shade400 : color),
            boxShadow: isSelected && !isPast
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ]
                : [],
          ),
          child: Text(
            isPast ? '$label (passed)' : label,
            style: TextStyle(
              color: isPast
                  ? Colors.grey.shade500
                  : isSelected
                  ? Colors.white
                  : color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
        ),
      ],
    );
  }

  // ===================== FORM STEP =====================

  Widget _buildFormStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, size: 18),
                onPressed: () => setState(() {
                  _step = 'calendar';
                  _saveError = null;
                }),
              ),
              const Expanded(
                child: Text(
                  'Your Details',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ),
              const SizedBox(width: 40),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  '📅 Pickup Schedule',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(_selectedDate!),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _selectedSlot!,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: Colors.blue.shade100, blurRadius: 12),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _formField(
                  controller: _nameController,
                  label: 'Name',
                  hint: 'Your name',
                  required: true,
                  readOnly: widget.cardNumber > 0,
                  onChanged: widget.cardNumber > 0
                      ? null
                      : (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _formField(
                  controller: _contactController,
                  label: 'Phone / Messenger Name',
                  hint: 'e.g. 09XX-XXX-XXXX or Facebook name',
                ),
                const SizedBox(height: 12),
                _formField(
                  controller: _addressController,
                  label: 'Address',
                  hint: 'Pickup address',
                  required: widget.requireAddress,
                  maxLines: 2,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _formField(
                  controller: _remarksController,
                  label: 'Remarks',
                  hint: 'Any special instructions (optional)',
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (widget.cardNumber == 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFCC02), width: 1),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚠️', style: TextStyle(fontSize: 16)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To help ensure your pickup goes smoothly, kindly provide your complete address or contact number so we can easily reach you.\n\n'
                      'If we\'re unable to contact you, we may not be able to process your order. Thank you very much for your understanding. 🙏\n\n'
                      'Order status tracking is currently available only for existing customers using their loyalty card number.\n\n'
                      'For new customers, the quick booking feature is not trackable. Rest assured, our staff will contact you to confirm your booking and keep you updated on its status.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF795548),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(
              _saveError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _saving ? null : _saveOrder,
            child: Builder(
              builder: (context) {
                final canSave =
                    _nameController.text.trim().isNotEmpty &&
                    (!widget.requireAddress ||
                        _addressController.text.trim().isNotEmpty);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: canSave
                          ? [const Color(0xFF42A5F5), const Color(0xFF1E88E5)]
                          : [Colors.grey.shade300, Colors.grey.shade400],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: canSave
                        ? [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.5),
                              blurRadius: 12,
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    _saving ? 'Saving...' : 'Confirm Booking',
                    style: TextStyle(
                      color: canSave ? Colors.white : Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    bool readOnly = false,
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.blueGrey,
                fontSize: 13,
              ),
            ),
            if (required)
              const Text(
                ' *',
                style: TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            if (readOnly)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text(
                  '(auto-filled)',
                  style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          maxLength: 100,
          readOnly: readOnly,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.blueGrey.shade200, fontSize: 13),
            filled: true,
            fillColor: readOnly ? Colors.grey.shade100 : Colors.blue.shade50,
            counterStyle: const TextStyle(fontSize: 10, color: Colors.blueGrey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
          ),
        ),
      ],
    );
  }
}
