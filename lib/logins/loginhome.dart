import 'package:flutter/material.dart';
import 'register_page.dart';
import 'login.dart'; // LoginPage burada olmalı

class loginHome extends StatelessWidget {
  const loginHome({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF1565C0);
    const accentColor = Color(0xFFFF1585);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/arkaplanresim.png',
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  const SizedBox(height: 10),
                  // Animasyonlu Giriş Yap Butonu (Aynı tasarımda!)
                  SizedBox(
                    width: 180,
                    height: 48,
                    child: _AnimatedSlideButton(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CustomPaint(
                              size: const Size(double.infinity, 48),
                              painter: DiagonalSplitPainter(),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => const LoginPage()),
                              );
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: primaryColor,
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            child: const Text(
                              'Giriş Yap',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.white,
                                    offset: Offset(0, 0),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Animasyonlu Üye Ol Butonu (Aynı tasarımda!)
                  SizedBox(
                    width: 180,
                    height: 48,
                    child: _AnimatedSlideButton(
                      delay: 230,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CustomPaint(
                              size: const Size(double.infinity, 48),
                              painter: DiagonalSplitPainter(),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const CustomerRegisterPage(),
                                ),
                              );
                            },
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              foregroundColor: accentColor,
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            child: const Text(
                              'Üye Ol',
                              style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                                shadows: [
                                  Shadow(
                                    blurRadius: 8,
                                    color: Colors.white,
                                    offset: Offset(0, 0),
                                  )
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                   const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================== ANİMASYONLU SLIDE + FADE WIDGET ======================
class _AnimatedSlideButton extends StatefulWidget {
  final Widget child;
  final int delay; // ms
  const _AnimatedSlideButton({required this.child, this.delay = 0});

  @override
  State<_AnimatedSlideButton> createState() => _AnimatedSlideButtonState();
}

class _AnimatedSlideButtonState extends State<_AnimatedSlideButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _slide = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _fade = Tween<double>(begin: 0, end: 1).animate(_controller);

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slide,
      child: FadeTransition(
        opacity: _fade,
        child: widget.child,
      ),
    );
  }
}

// ================== DİAGONAL SPLIT PAINTER (EĞİK BÖLMELİ) ======================
class DiagonalSplitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Sol üstten sağ alta eğik şekilde iki alanı doldur
    final paintLeft = Paint()
      ..color = const Color(0xFF795548).withOpacity(0.8); // Kahverengi
    final paintRight = Paint()
      ..color = const Color(0xFFD7CCC8); // bej

    // Sol bölge (üst sol, alt sol, çizgiye kadar)
    final pathLeft = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width * 0.7, 0)
      ..lineTo(size.width * 0.3, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(pathLeft, paintLeft);

    // Sağ bölge (üst sağ, alt sağ, çizgiye kadar)
    final pathRight = Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * 0.3, size.height)
      ..close();
    canvas.drawPath(pathRight, paintRight);

    // Eğik bölme çizgisi (parlak beyaz)
    final slashPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..strokeWidth = 5
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.7, 0),
      Offset(size.width * 0.3, size.height),
      slashPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}