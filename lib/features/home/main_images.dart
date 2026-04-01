import 'package:flutter/material.dart';

/// Scrollable images shown in the main page:
/// welcome.png, Services.png, sample_loyalty_card.png
class MainImages extends StatelessWidget {
  const MainImages({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/welcome.png',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/Services.png',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/images/sample_loyalty_card.png',
            width: double.infinity,
            fit: BoxFit.fitWidth,
          ),
        ),
      ],
    );
  }
}
