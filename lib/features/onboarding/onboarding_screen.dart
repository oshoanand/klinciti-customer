import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish; // Callback to trigger navigation to Auth/Home

  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Define the 2 screens' content
  // Note: Ensure you have added these images to your assets folder and pubspec.yaml
  final List _pages = [
    {
      'title': 'Быстрый поиск\nисполнителей',
      'subtitle': 'Уборка дома, уход за садом или мелкий ремонт. Найдите проверенного мастера за пару кликов.',
      'icon': Icons.cleaning_services_rounded,
      'image': 'assets/images/onboarding_1.webp',
      'color': const Color(0xFF3B82F6), // Blue
    },
    {
      'title': 'Вывоз мусора\nбез хлопот',
      'subtitle': 'Избавьтесь от строительного и бытового мусора легко и быстро. Создайте заявку, а мы всё организуем.',
      'icon': Icons.delete_sweep_rounded,
      'image': 'assets/images/onboarding_2.webp',
      'color': const Color(0xFF10B981), // Emerald
    },
  ];

  void _onNext() async {
    if (_currentPage == _pages.length - 1) {
      // Save flag and finish
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      widget.onFinish();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Make status bar transparent for edge-to-edge design
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark slate base
      body: Stack(
        children: [
          // 1. Swipable Background & Content (with parallax)
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              return _buildPageContent(
                index: index,
                title: _pages[index]['title'],
                subtitle: _pages[index]['subtitle'],
                icon: _pages[index]['icon'],
                color: _pages[index]['color'],
                imagePath: _pages[index]['image'],
              );
            },
          ),

          // 2. Fixed Skip Button (Top Right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 24,
            child: AnimatedOpacity(
              opacity: _currentPage == _pages.length - 1 ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('has_seen_onboarding', true);
                  widget.onFinish();
                },
                child: const Text(
                  'Пропустить',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ),

          // 3. Fixed Bottom Section (Indicators & CTA Button)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 32,
                right: 32,
                top: 32,
                bottom: MediaQuery.of(context).padding.bottom + 32,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dot Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => _buildDot(index),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // CTA Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _onNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white, // High contrast button
                        foregroundColor: const Color(0xFF0F172A),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _currentPage == _pages.length - 1
                            ? 'Начать работу'
                            : 'Далее',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String imagePath,
  }) {
    // Get screen width for horizontal parallax calculation
    final screenWidth = MediaQuery.of(context).size.width;

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        // Calculate the swipe offset for this specific page
        double pageOffset = index.toDouble();
        if (_pageController.position.haveDimensions) {
          pageOffset = _pageController.page ?? index.toDouble();
        }

        // difference is 0 when fully visible, grows to 1 or -1 as it swipes away
        double difference = (pageOffset - index).clamp(-1.0, 1.0);

        // Foreground Text: Fade out and slide down slightly
        double textOpacity = (1 - difference.abs()).clamp(0.0, 1.0);
        double textTranslateY = difference.abs() * 50.0;

        // Background Image: Move horizontally in the opposite direction of the swipe
        // (0.3 means it moves 30% slower than the actual page swipe)
        double imageTranslateX = difference * screenWidth * 0.3;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Background Image with Horizontal Parallax
            Transform.translate(
              offset: Offset(imageTranslateX, 0),
              child: Image.asset(
                imagePath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: color),
              ),
            ),

            // Translucent Theme Tint
            Container(color: color.withOpacity(0.35)),

            // Dark elegant gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF0F172A).withOpacity(0.5),
                    const Color(0xFF0F172A).withOpacity(0.95),
                    const Color(0xFF0F172A),
                  ],
                  stops: const [0.0, 0.45, 0.75, 1.0],
                ),
              ),
            ),

            // Foreground Content with Vertical Parallax and Fade
            Opacity(
              opacity: textOpacity,
              child: Transform.translate(
                offset: Offset(0, textTranslateY),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Glassmorphism Icon Container
                      ClipRRect(
                        borderRadius: BorderRadius.circular(100),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(icon, size: 70, color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Typography
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 34,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),

                      // Spacing to keep content above the fixed bottom section
                      const SizedBox(height: 200),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDot(int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      height: 8,
      width: _currentPage == index ? 24 : 8,
      decoration: BoxDecoration(
        color: _currentPage == index
            ? Colors.white
            : Colors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
