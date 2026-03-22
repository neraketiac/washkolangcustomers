import 'package:flutter/material.dart';
import 'package:washkolangcustomer/main.dart';
import 'package:washkolangcustomer/loyalty_single.dart';
import 'package:washkolangcustomer/pickup_booking.dart';
import 'package:washkolangcustomer/rider_location.dart';
import 'package:web/web.dart' as web;

class EnterLoyaltyCode extends StatefulWidget {
  const EnterLoyaltyCode({super.key});

  @override
  State<EnterLoyaltyCode> createState() => _EnterLoyaltyCodeState();
}

class _EnterLoyaltyCodeState extends State<EnterLoyaltyCode>
    with TickerProviderStateMixin {
  static const String _version = '1.11';
  static const String _storageKey = 'customer_code';
  late AnimationController controller;
  late Animation<double> animation;
  late AnimationController controllerbubble;
  late Animation<double> animationbubble;

  final TextEditingController _controller = TextEditingController();

  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkSavedCode();

    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    animation = Tween<double>(begin: -6, end: 6).animate(controller);

    controllerbubble = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    animationbubble = Tween<double>(
      begin: -10,
      end: 16,
    ).animate(controllerbubble);
  }

  @override
  void dispose() {
    controller.dispose();
    controllerbubble.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ================= AUTO LOGIN =================

  Future<void> _checkSavedCode() async {
    final savedCode = web.window.localStorage.getItem(_storageKey);
    if (savedCode == null) return;

    final isValid = await _validateCode(savedCode);
    if (isValid && mounted) {
      _navigateToCard(savedCode);
    }
  }

  Future<bool> _validateCode(String code) async {
    if (code.contains('#')) return false;

    final snap = await forthFirestore
        .collection('loyalty')
        .where('cardNumber', isEqualTo: int.tryParse(code) ?? 0)
        .limit(1)
        .get();

    return snap.docs.isNotEmpty;
  }

  // ================= LOGIN =================

  Future<void> _login() async {
    if (_loading) return;

    final code = _controller.text.trim();

    if (code.isEmpty) {
      setState(() => _error = 'Please enter your card number');
      return;
    }

    // Admin code — open location sharing panel
    // if (code == '1346792580') {
    //   _controller.clear();
    //   showDialog(context: context, builder: (_) => const AdminRiderPanel());
    //   return;
    // }

    setState(() {
      _loading = true;
      _error = null;
    });

    final isValid = await _validateCode(code);

    if (!mounted) return;

    if (isValid) {
      web.window.localStorage.setItem(_storageKey, code);
      _navigateToCard(code);
    } else {
      setState(() {
        _error = 'Invalid card number';
        _loading = false;
      });
    }
  }

  void _navigateToCard(String code) {
    _controller.clear();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyLoyaltyCard(code)),
    ).then((_) {
      // Clear saved code so auto-login doesn't re-trigger on back
      web.window.localStorage.removeItem(_storageKey);
      if (mounted) setState(() => _loading = false);
    });
  }

  // ================= UI =================

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
        child: SafeArea(child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: animationbubble,
                  builder: (_, child) {
                    return Transform.translate(
                      offset: Offset(0, animationbubble.value),
                      child: child,
                    );
                  },
                  child: const Text(
                    "🫧",
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),

                //Image.asset("assets/images/washkolang.png", width: 280),
                AnimatedBuilder(
                  animation: animation,
                  builder: (_, child) {
                    return Transform.translate(
                      offset: Offset(0, animation.value),
                      child: child,
                    );
                  },
                  child: Image.asset(
                    "assets/images/washkolang.png",
                    width: 280,
                  ),
                ),

                AnimatedBuilder(
                  animation: animationbubble,
                  builder: (_, child) {
                    return Transform.translate(
                      offset: Offset(0, animationbubble.value),
                      child: child,
                    );
                  },
                  child: const Text(
                    "🫧",
                    style: TextStyle(
                      fontSize: 44,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),

            const Text(
              "Laundry Hub",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              "Loyalty Card Entry v$_version",
              style: TextStyle(fontSize: 13, color: Colors.blueGrey),
            ),
            const SizedBox(height: 16),

            // Display
            Container(
              width: 250,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(.85),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.blue.shade100, blurRadius: 12),
                ],
              ),
              child: Center(
                child: Text(
                  _controller.text.isEmpty
                      ? "Enter Card Number"
                      : _controller.text,
                  style: const TextStyle(
                    fontSize: 16,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            _buildKeypad(),

            const SizedBox(height: 8),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),

            const SizedBox(height: 25),

            // Pickup + Facebook row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PickupBookingScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF66BB6A), Color(0xFF388E3C)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.local_shipping,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Pickup',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'or',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 12),
                  ),
                ),
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
                        Text('💬', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 5),
                        Text(
                          'Messenger',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Check Rider Status
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RiderLocationScreen(),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueGrey.shade200),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.electric_moped,
                          size: 16,
                          color: Colors.blueGrey,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Check Rider Status',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget facebookButton() {
    return GestureDetector(
      onTap: () {
        web.window.open('https://m.me/WashkoLangLaundryHub', '_blank');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1877F2),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(color: Color.fromRGBO(24, 119, 242, 0.4), blurRadius: 12),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('💬', style: TextStyle(fontSize: 16)),
            SizedBox(width: 8),
            Text(
              'Message Us on Facebook',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= KEYPAD =================

  Widget _buildKeypad() {
    // Layout: 1-9 in rows, then ⌫ / 0 / ✓
    const digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9"];

    return SizedBox(
      width: 250,
      child: Column(
        children: [
          // Digit rows 1–9
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: digits.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.2,
            ),
            itemBuilder: (_, i) => _keyButton(digits[i]),
          ),
          const SizedBox(height: 10),
          // Bottom row: ⌫  0  ✓
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(child: _keyButton("⌫")),
                const SizedBox(width: 10),
                Expanded(child: _keyButton("0")),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _loading ? null : _login,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withValues(alpha: 0.5),
                            blurRadius: 8,
                            offset: const Offset(2, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '✓',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyButton(String value) {
    return GestureDetector(
      onTap: () {
        setState(() {
          if (value == "⌫") {
            if (_controller.text.isNotEmpty) {
              _controller.text = _controller.text.substring(
                0,
                _controller.text.length - 1,
              );
            }
          } else {
            _controller.text += value;
          }
        });
      },
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.shade200,
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blueAccent,
            ),
          ),
        ),
      ),
    );
  }

  // ================= BUTTONS =================
}
