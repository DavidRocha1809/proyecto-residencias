import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'admin_home_page.dart';
import 'teacher_home_page.dart';

class LoginPage extends StatefulWidget {
  static const route = '/login';
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

enum _Mode { signIn, signUp }

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _storage = const FlutterSecureStorage();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  final bool _remember = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveRemembered(String email, String password) async {
    if (_remember) {
      await _storage.write(key: 'auth_email', value: email);
      await _storage.write(key: 'auth_password', value: password);
    } else {
      await _storage.deleteAll();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    try {
      // 🔹 CASO 1: REGISTRO
      if (_mode == _Mode.signUp) {
        final cred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: pass);

        // Usuario nuevo -> queda como pendiente
        await FirebaseFirestore.instance
            .collection('users')
            .doc(cred.user!.uid)
            .set({
          'email': email,
          'name': _nameCtrl.text.trim(),
          'role': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });

        // Cerramos sesión y mostramos mensaje
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;
        setState(() {
          _busy = false;
          _mode = _Mode.signIn; // cambiamos la vista a "Iniciar sesión"
          _error =
          'Tu cuenta ha sido registrada y está pendiente de autorización. '
              'Ponerse en contacto con un administrador para revisar el acceso.';
        });
        return; // 👈 IMPORTANTE: no seguimos al flujo de login
      }

      // 🔹 CASO 2: LOGIN
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: pass,
      );

      await _saveRemembered(email, pass);

      final uid = cred.user!.uid;
      final snap =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (!snap.exists) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error =
          'Tu usuario no tiene rol asignado. Contacta con el administrador.';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      final role = snap['role'];

      // 🚫 Bloquear usuarios pendientes al iniciar sesión
      if (role == 'pending') {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error =
          'Tu cuenta está pendiente de autorización. Ponerse en contacto con un administrador para revisar el acceso.';
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (!mounted) return;
      setState(() => _busy = false);

      // 🔹 Navegación según rol
      Future.microtask(() {
        if (!mounted) return;
        if (role == 'admin') {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const AdminHomePage()),
          );
        } else {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const TeacherHomePage()),
          );
        }
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }


  Future<void> _resetPasswordPrompt() async {
  final emailController = TextEditingController(text: _emailCtrl.text);

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Recuperar contraseña',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ingresa el correo asociado a tu cuenta para recibir el enlace de recuperación.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.mail_outline),
                  labelText: 'Correo electrónico',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        final mail = emailController.text.trim();

                        if (mail.isEmpty || !mail.contains('@')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Correo inválido'),
                            ),
                          );
                          return;
                        }

                        Navigator.of(ctx).pop();

                        try {
                          await FirebaseAuth.instance
                              .sendPasswordResetEmail(email: mail);

                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Si el correo existe en el sistema, se envió un enlace de restablecimiento.',
                              ),
                            ),
                          );
                        } on FirebaseAuthException catch (e) {
                          if (!mounted) return;

                          String msg;
                          switch (e.code) {
                            case 'invalid-email':
                              msg = 'El correo no tiene un formato válido.';
                              break;
                            case 'user-not-found':
                              msg =
                                  'No existe ninguna cuenta registrada con ese correo.';
                              break;
                            case 'missing-android-pkg-name':
                            case 'missing-ios-bundle-id':
                            case 'invalid-continue-uri':
                            case 'unauthorized-continue-uri':
                              msg =
                                  'Falta configurar el dominio de acción / enlace de redirección en Firebase Auth.';
                              break;
                            default:
                              msg =
                                  e.message ?? 'Error al enviar el correo: ${e.code}';
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error inesperado: $e'),
                            ),
                          );
                        }
                      },
                      child: const Text('Enviar enlace'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

  

  Widget _buildCard(BuildContext context) {
    final isUp = _mode == _Mode.signUp;
    final width = MediaQuery.of(context).size.width * 0.86;
    final cardWidth = width > 420 ? 420.0 : width;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: cardWidth),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFDF0F1),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6))
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12)),
                    child: SizedBox(
                        width: 86,
                        height: 86,
                        child:
                            Image.asset('assets/images/logo_cetis31.png')),
                  ),
                  const SizedBox(height: 12),
                  const Text('Sistema de Asistencia',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('CETIS 31\nControl de Asistencia Escolar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 18),
                  if (_error != null)
                    Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(10)),
                        child: Text(_error!,
                            style: TextStyle(color: Colors.red.shade700))),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.person_outline),
                      labelText: 'Correo electrónico',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isUp)
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.badge_outlined),
                        labelText: 'Nombre completo',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none),
                      ),
                    ),
                  if (isUp) const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: const Icon(Icons.lock_outline),
                      labelText: 'Contraseña',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(isUp ? 'Crear cuenta' : 'Iniciar Sesión'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Column(children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () =>
                              setState(() => _mode =
                                  isUp ? _Mode.signIn : _Mode.signUp),
                      child: Text(
                        isUp
                            ? '¿Ya tienes cuenta? Inicia sesión'
                            : '¿No tienes cuenta? Regístrate',
                        style: const TextStyle(color: Color(0xFF8B0000)),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _resetPasswordPrompt,
                      child: const Text(
                        '¿Olvidaste tu contraseña? Recuperar',
                        style: TextStyle(color: Color(0xFF8B0000)),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.white, body: SafeArea(child: _buildCard(context)));
  }
}
