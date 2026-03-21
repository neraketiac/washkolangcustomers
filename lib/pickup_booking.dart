import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:washkolangcustomer/model/loyalty_order_online_model.dart';
import 'package:washkolangcustomer/model/model_rider_availability.dart';

// slot key → display label
const _slotLabels = {
  'slot7to9': '7-9am',
  'slot9to12': '9-12pm',
  'slot12to4': '12-4pm',
  'slot4to9': '4-9pm',
};

class PickupBookingScreen extends StatefulWidget {
  const PickupBookingScreen({super.key});

  @override
  State<PickupBookingScreen> createState() => _PickupBookingScreenState();
}

class _PickupBookingScreenState extends State<PickupBookingScreen> {
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDate;
  ModelRiderAvailability? _selectedAvailability;
  String? _selectedSlot;
  bool _loadingAvailability = false;
  final Map<String, ModelRiderAvailability> _availabilityCache = {};

  String _step = 'calendar'; // 'calendar' | 'form'

  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadMonthAvailability(_focusedMonth);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadMonthAvailability(DateTime month) async {
    setState(() => _loadingAvailability = true);
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    final snap = await FirebaseFirestore.instance
        .collection('Rider_schedule')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    for (final doc in snap.docs) {
      final avail = ModelRiderAvailability.fromMap(doc.data());
      _availabilityCache[avail.docId] = avail;
    }
    setState(() => _loadingAvailability = false);
  }

  String _docId(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  ModelRiderAvailability? _availabilityFor(DateTime d) =>
      _availabilityCache[_docId(d)];

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

  void _prevMonth() {
    final prev = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    setState(() {
      _focusedMonth = prev;
      _selectedDate = null;
      _selectedAvailability = null;
      _selectedSlot = null;
    });
    _loadMonthAvailability(prev);
  }

  void _nextMonth() {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    setState(() {
      _focusedMonth = next;
      _selectedDate = null;
      _selectedAvailability = null;
      _selectedSlot = null;
    });
    _loadMonthAvailability(next);
  }

  void _onDayTap(DateTime day) {
    final avail = _availabilityFor(day);
    if (avail == null || !avail.hasAnySlot) return;
    setState(() {
      _selectedDate = day;
      _selectedAvailability = avail;
      _selectedSlot = null;
    });
  }

  Future<void> _saveOrder() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _saveError = 'Name is required');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final order = LoyaltyOrderOnlineModel(
      name: name,
      contact: _contactController.text.trim(),
      address: _addressController.text.trim(),
      scheduleDate: _selectedDate!,
      timeSlot: _selectedSlot!,
      createdAt: Timestamp.now(),
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
              Navigator.pop(context);
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
          child: _step == 'calendar' ? _buildCalendarStep() : _buildFormStep(),
        ),
      ),
    );
  }

  // ===================== CALENDAR STEP =====================

  Widget _buildCalendarStep() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedMonth.year,
      _focusedMonth.month,
    );
    // weekday: Mon=1..Sun=7, we want Sun=0
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;
    final totalCells = firstWeekday + daysInMonth;

    return Column(
      children: [
        // ── top bar ──
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

        // ── month nav ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _prevMonth,
                icon: const Icon(Icons.chevron_left, color: Colors.blueGrey),
              ),
              Text(
                '${_monthName(_focusedMonth.month)} ${_focusedMonth.year}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blueGrey,
                ),
              ),
              IconButton(
                onPressed: _nextMonth,
                icon: const Icon(Icons.chevron_right, color: Colors.blueGrey),
              ),
            ],
          ),
        ),

        // ── day-of-week header ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
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

        // ── calendar grid ──
        if (_loadingAvailability)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                children: [
                  // Build rows of 7
                  for (int row = 0; row < (totalCells / 7).ceil(); row++)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(7, (col) {
                        final index = row * 7 + col;
                        if (index < firstWeekday ||
                            index >= firstWeekday + daysInMonth) {
                          return const Expanded(child: SizedBox(height: 72));
                        }
                        final day = index - firstWeekday + 1;
                        final date = DateTime(
                          _focusedMonth.year,
                          _focusedMonth.month,
                          day,
                        );
                        final isPast = date.isBefore(today);
                        final avail = _availabilityFor(date);
                        final hasSlot = avail != null && avail.hasAnySlot;
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
                                vertical: 4,
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
                                  // day number
                                  Text(
                                    '$day',
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
                                  // slot badges
                                  if (!isPast && avail != null)
                                    ..._slotBadges(avail, isSelected),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),

                  const SizedBox(height: 12),

                  // ── legend ──
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      _legendItem(const Color(0xFF43A047), '7-9am'),
                      _legendItem(const Color(0xFF1E88E5), '9-12pm'),
                      _legendItem(const Color(0xFFFB8C00), '12-4pm'),
                      _legendItem(const Color(0xFF8E24AA), '4-9pm'),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ── slot picker (shown after date tap) ──
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

                  // ── next button ──
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

  /// tiny colored dots per slot
  List<Widget> _slotBadges(ModelRiderAvailability avail, bool isSelected) {
    final active = <Color>[];
    if (avail.slot7to9) active.add(const Color(0xFF43A047));
    if (avail.slot9to12) active.add(const Color(0xFF1E88E5));
    if (avail.slot12to4) active.add(const Color(0xFFFB8C00));
    if (avail.slot4to9) active.add(const Color(0xFF8E24AA));

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
    final entries = {
      'slot7to9': avail.slot7to9,
      'slot9to12': avail.slot9to12,
      'slot12to4': avail.slot12to4,
      'slot4to9': avail.slot4to9,
    };
    final colors = {
      'slot7to9': const Color(0xFF43A047),
      'slot9to12': const Color(0xFF1E88E5),
      'slot12to4': const Color(0xFFFB8C00),
      'slot4to9': const Color(0xFF8E24AA),
    };

    return entries.entries.where((e) => e.value).map((e) {
      final label = _slotLabels[e.key]!;
      final color = colors[e.key]!;
      final isSelected = _selectedSlot == label;
      return GestureDetector(
        onTap: () => setState(() => _selectedSlot = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.4),
                      blurRadius: 8,
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : color,
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

          // summary banner
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
                  hint: 'Pickup address (optional)',
                  maxLines: 2,
                ),
              ],
            ),
          ),

          // ── contact warning ──
          const SizedBox(height: 12),
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
                    'To make sure your pickup goes smoothly, please provide a phone number or Facebook Messenger name so we can reach you.\n\n'
                    'If we are unable to contact you, we may not be able to process your order. Thank you for your understanding! 🙏',
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 13),
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
              child: Text(
                _saving ? 'Saving...' : 'Confirm Booking',
                style: const TextStyle(
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
    );
  }

  Widget _formField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool required = false,
    int maxLines = 1,
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
          ],
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.blueGrey.shade200, fontSize: 13),
            filled: true,
            fillColor: Colors.blue.shade50,
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
