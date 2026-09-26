import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/brand_mark.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eased = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    return Scaffold(
      body: AmbientBackground(
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: ScaleTransition(
              scale: Tween<double>(begin: .72, end: 1).animate(eased),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BrandMark(size: 86),
                  SizedBox(height: 22),
                  Text(
                    'دنیای تماشا، دوباره روشن شد',
                    style: TextStyle(color: MovieColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
