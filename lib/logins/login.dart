import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'getpass.dart'; // AnimatedLabelTextField sınıfını kullanmak için
import 'package:shared_preferences/shared_preferences.dart';
import '../home/home_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'register_page.dart';
import 'reset_password.dart';
import 'forgot_password.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String _errorMessage = '';

  void _performLogin() async {
    setState(() {
      _errorMessage = '';
    });

    final email = _usernameController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Lütfen tüm alanları doldurun.';
      });
      return;
    }

    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = userCredential.user;

      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        await prefs.setString('user_uid', user.uid);

        final userSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('appcustomer_email', isEqualTo: email)
            .limit(1)
            .get();

        if (userSnapshot.docs.isNotEmpty) {
          final data = userSnapshot.docs.first.data();

          final userIdRaw = data['user_id'];
          if (userIdRaw != null) {
            int? userId;
            if (userIdRaw is int) {
              userId = userIdRaw;
            } else if (userIdRaw is String) {
              userId = int.tryParse(userIdRaw);
            }
            if (userId != null) await prefs.setInt('user_id', userId);
          }

          final userTypeRaw = data['user_type'];
          if (userTypeRaw != null)
            await prefs.setString('user_type', userTypeRaw.toString());

          final name = data['appcustomer_name'];
          if (name != null) await prefs.setString('appcustomer_name', name.toString());

          final customerEmail = data['appcustomer_email'];
          if (customerEmail != null)
            await prefs.setString('appcustomer_email', customerEmail.toString());

          final tc = data['appcustomer_tc'];
          if (tc != null) await prefs.setString('appcustomer_tc', tc.toString());

          final phone = data['app_phone'];
          if (phone != null) await prefs.setString('app_phone', phone.toString());

          final parentIdRaw = data['parent_id'];
          if (parentIdRaw != null) {
            int? parentId;
            if (parentIdRaw is int) {
              parentId = parentIdRaw;
            } else if (parentIdRaw is String) {
              parentId = int.tryParse(parentIdRaw);
            }
            if (parentId != null) await prefs.setInt('parent_id', parentId);
          }

          final firebaseUid = data['firebase_uid'];
          if (firebaseUid != null) {
            await prefs.setString('firebase_uid', firebaseUid.toString());
          }
        } else {
          setState(() {
            _errorMessage = "Kullanıcı Firestore'da bulunamadı.";
          });
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Giriş başarılı!')),
        );

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      } else {
        setState(() {
          _errorMessage = 'Giriş başarısız!';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        setState(() {
          _errorMessage = 'Firebase: Kullanıcı bulunamadı.';
        });
      } else if (e.code == 'wrong-password') {
        setState(() {
          _errorMessage = 'Firebase: Şifre yanlış.';
        });
      } else if (e.code == 'invalid-email') {
        setState(() {
          _errorMessage = 'Firebase: Geçersiz e-posta adresi.';
        });
      } else {
        setState(() {
          _errorMessage = 'Firebase hatası: ${e.message}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Firebase giriş hatası: $e';
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Renk tonları
    const primaryColor = Color(0xFF1585FF); // mavi
    const secondaryColor = Color(0xFF5E17EB); // mor ton
    const accentColor = Color(0xFFFF1585); // pembe ton
    final bej = Colors.white;
    final turuncu = Color(0xFFE65100);

    final inputShadow = [
      BoxShadow(
        color: turuncu.withOpacity(0.5),
        blurRadius: 32,
        spreadRadius: 6,
        offset: const Offset(0, 0),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: 300,
                height: 300,
                child: Image.asset(
                  'assets/arkabacks.png',
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: bej,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: inputShadow,
                  border: Border.all(
                    color: turuncu,
                    width: 2.0,
                  ),
                ),
                child: AnimatedLabelTextField(
                  controller: _usernameController,
                  label: 'Kullanıcı Adı',
                  icon: Icons.person,
                  keyboardType: TextInputType.text,
                  primaryColor: turuncu,
                  accentColor: accentColor,
                  borderRadius: 32,
                  fillColor: Colors.transparent,
                  textColor: Colors.brown[800],
                  labelTextColor: turuncu,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: bej,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: inputShadow,
                  border: Border.all(
                    color: turuncu,
                    width: 2.0,
                  ),
                ),
                child: AnimatedLabelTextField(
                  controller: _passwordController,
                  label: 'Parola',
                  icon: Icons.lock,
                  isPassword: true,
                  keyboardType: TextInputType.text,
                  primaryColor: turuncu,
                  accentColor: accentColor,
                  borderRadius: 32,
                  fillColor: Colors.transparent,
                  textColor: Colors.brown[800],
                  labelTextColor: turuncu,
                ),
              ),
              const SizedBox(height: 25),
              if (_errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 15.0),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ElevatedButton(
                onPressed: _performLogin,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  elevation: 2,
                  shadowColor: accentColor.withOpacity(0.9),
                ),
                child: const Text('Giriş Yap'),
              ),
              const SizedBox(height: 15),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CustomerRegisterPage()),
                  );
                },
                child: Text(
                  'Hesabınız yok mu? Kayıt Olun',
                  style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const OtpRequestPage()),
                  );
                },
                child: Text(
                  'RüzgarNet Abonesiyim ',
                  style: TextStyle(color: Color(0xFFE65100).withOpacity(0.96), fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
                  );
                },
                child: Text(
                  'Şifremi Unuttum?',
                  style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================================
// 🔹 AnimatedLabelTextField Widget
// ================================
class AnimatedLabelTextField extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPassword;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  final Color? primaryColor;
  final Color? accentColor;
  final double borderRadius;
  final Color? fillColor;
  final Color? textColor;
  final Color? labelTextColor;

  const AnimatedLabelTextField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.keyboardType,
    this.isPassword = false,
    this.primaryColor,
    this.accentColor,
    this.borderRadius = 12,
    this.fillColor,
    this.textColor,
    this.labelTextColor,
  });

  @override
  State<AnimatedLabelTextField> createState() => _AnimatedLabelTextFieldState();
}

class _AnimatedLabelTextFieldState extends State<AnimatedLabelTextField>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _offsetAnimation;
  late FocusNode _focusNode;
  late bool _obscureText;

  @override
  void initState() {
    super.initState();

    _obscureText = widget.isPassword;

    _focusNode = FocusNode();
    _focusNode.addListener(_handleFocusChange);

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: const Offset(0, -1.2),
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    if (widget.controller.text.isNotEmpty) {
      _animationController.forward();
    }
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus || widget.controller.text.isNotEmpty) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  void _toggleObscure() {
    setState(() {
      _obscureText = !_obscureText;
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.primaryColor ?? Colors.orange;
    final accentColor = widget.accentColor ?? Colors.orangeAccent;
    final fillColor = widget.fillColor ?? Colors.transparent;
    final textColor = widget.textColor ?? Colors.brown[800];
    final labelTextColor = widget.labelTextColor ?? Colors.orange;

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Stack(
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: _obscureText,
            keyboardType: widget.keyboardType,
            cursorColor: borderColor,
            style: TextStyle(fontSize: 17, color: textColor),
            decoration: InputDecoration(
              filled: true,
              fillColor: fillColor,
              border: InputBorder.none, // Sadece dış container borderı var!
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              prefixIcon: Icon(widget.icon, color: borderColor),
              suffixIcon: widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscureText ? Icons.visibility_off : Icons.visibility,
                        color: borderColor.withOpacity(0.8),
                      ),
                      onPressed: _toggleObscure,
                    )
                  : null,
              contentPadding: const EdgeInsets.fromLTRB(16, 28, 12, 14),
              isDense: true,
            ),
          ),
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _offsetAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: _offsetAnimation.value * 24,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 52),
                    child: Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: _focusNode.hasFocus || widget.controller.text.isNotEmpty ? 13 : 16,
                        fontWeight: FontWeight.bold,
                        color: labelTextColor,
                        backgroundColor: fillColor,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}