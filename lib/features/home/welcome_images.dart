import 'package:flutter/material.dart';

/// Shows first_pic, price_list, rules on first load.
/// Call [WelcomeImagesViewer.show(context)] to open.
class WelcomeImagesViewer extends StatefulWidget {
  const WelcomeImagesViewer({super.key});

  static const images = [
    'assets/images/first_pic.jpg',
    'assets/images/price_list.jpg',
    'assets/images/rules.jpg',
  ];

  static void show(BuildContext context) {
    for (final img in images) {
      precacheImage(AssetImage(img), context);
    }
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const WelcomeImagesViewer(),
    );
  }

  @override
  State<WelcomeImagesViewer> createState() => _WelcomeImagesViewerState();
}

class _WelcomeImagesViewerState extends State<WelcomeImagesViewer> {
  int _index = 0;

  void _next() {
    if (_index < WelcomeImagesViewer.images.length - 1) {
      setState(() => _index++);
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white, size: 22),
                label: const Text(
                  'Close all',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    WelcomeImagesViewer.images[_index],
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_index + 1} / ${WelcomeImagesViewer.images.length}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      elevation: 4,
                    ),
                    child: Text(
                      _index < WelcomeImagesViewer.images.length - 1
                          ? 'Next ->'
                          : 'Close',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
