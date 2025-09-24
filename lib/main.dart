import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive
  final dir = await pp.getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);
  await Hive.openBox('sessions');
  await Hive.openBox('groups');

  // Locale
  await initializeDateFormatting('es_MX');
  Intl.defaultLocale = 'es_MX';

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const AsistenciasApp());
}

class AsistenciasApp extends StatefulWidget {
  const AsistenciasApp({super.key});
  @override
  State<AsistenciasApp> createState() => _AsistenciasAppState();
}

class _AsistenciasAppState extends State<AsistenciasApp> {
  final _storage = const FlutterSecureStorage();
  bool _triedAutoLogin = false;

  @override
  void initState() {
    super.initState();
    _autoLoginIfNeeded();
  }

  Future<void> _autoLoginIfNeeded() async {
    // Si ya hay sesión activa, no hacemos nada.
    if (FirebaseAuth.instance.currentUser != null) {
      setState(() => _triedAutoLogin = true);
      return;
    }

    // Lee credenciales guardadas (si existen) y prueba login silencioso.
    final email = await _storage.read(key: 'auth_email');
    final pass  = await _storage.read(key: 'auth_password');

    if (email != null && pass != null) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );
      } catch (_) {
        // Si falla, seguimos a LoginPage normal.
      }
    }
    setState(() => _triedAutoLogin = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistema de Asistencia - CETIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFFB71C1C)),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'MX'), Locale('en', 'US')],
      locale: const Locale('es', 'MX'),
      home: !_triedAutoLogin
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, s) {
                if (s.connectionState == ConnectionState.waiting) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }
                final user = s.data;
                if (user == null) return const LoginPage();

                final teacherName =
                    user.displayName?.trim().isNotEmpty == true
                        ? user.displayName!
                        : (user.email?.split('@').first ?? 'Docente');

                return DashboardPage(teacherName: teacherName);
              },
            ),
    );
  }
}
