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
          // TAM EKRAN ARKA PLAN GÖRSELİ
          Positioned.fill(
            child: Image.asset(
              'assets/denes9.png',
              fit: BoxFit.fill,
            ),
          ),
          // MERKEZDEKİ BUTONLAR VE LOGO
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center, // Ortala
                children: <Widget>[
                  const SizedBox(height: 140),
                  // Animasyonlu Giriş Yap Butonu
                  SizedBox(
                    width: 180, // BUTON ENİNİ DARALT
                    child: _AnimatedSlideButton(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => const LoginPage()),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: primaryColor,
                          shadowColor: accentColor.withOpacity(0.01),
                          elevation: 0,
                          minimumSize: const Size(0, 44), // Boyu dar tut
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: primaryColor, width: 2),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8), // Daha dar
                          textStyle: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        child: Text(
                          'Giriş Yap',
                          style: TextStyle(
                            color: primaryColor, // Kenar rengiyle aynı
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Animasyonlu Üye Ol Butonu
                  SizedBox(
                    width: 180, // BUTON ENİNİ DARALT
                    child: _AnimatedSlideButton(
                      delay: 230,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    const CustomerRegisterPage()),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: accentColor, // Yazı ve icon rengi
                          side: BorderSide(color: accentColor, width: 2),
                          minimumSize: const Size(0, 44), // Boyu dar tut
                          padding: const EdgeInsets.symmetric(vertical: 8), // Daha dar
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        child: Text(
                          'Üye Ol',
                          style: TextStyle(
                            
                            
                            color: accentColor, // Kenar rengiyle aynı
                            fontWeight: FontWeight.bold,
                          ),
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