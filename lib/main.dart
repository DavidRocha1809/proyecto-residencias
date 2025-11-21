// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pages/login_page.dart';
import 'pages/admin_home_page.dart';
import 'pages/teacher_home_page.dart';

import 'pages/edit_attendance_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AsistenciasApp());
}

class AsistenciasApp extends StatefulWidget {
  const AsistenciasApp({super.key});
  @override
  State<AsistenciasApp> createState() => _AsistenciasAppState();
}

class _AsistenciasAppState extends State<AsistenciasApp> {
  final _storage = const FlutterSecureStorage();

  late final Future<void> _bootstrap;
  bool _triedAutoLogin = false;

  @override
  void initState() {
    super.initState();
    _bootstrap = _initServices();
  }

  Future<void> _initServices() async {
    final dir = await pp.getApplicationDocumentsDirectory();
    await Hive.initFlutter(dir.path);
    await Hive.openBox('sessions');
    await Hive.openBox('groups');

    await initializeDateFormatting('es_MX');
    Intl.defaultLocale = 'es_MX';

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await _autoLoginIfNeeded();
  }

  Future<void> _autoLoginIfNeeded() async {
    if (FirebaseAuth.instance.currentUser != null) {
      _triedAutoLogin = true;
      return;
    }
    final email = await _storage.read(key: 'auth_email');
    final pass = await _storage.read(key: 'auth_password');
    if (email != null && pass != null) {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );
      } catch (_) {}
    }
    _triedAutoLogin = true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Asistencias - CETIS 31',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFB71C1C),
      ),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'MX'), Locale('en', 'US')],
      locale: const Locale('es', 'MX'),

      // 🔹 Aquí se registran las rutas globales
      routes: {
        '/home': (context) => const TeacherHomePage(),
        '/editAttendance': (context) => EditAttendancePage(
              docId: '',
              subject: '',
              groupName: '',
              start: '',
              end: '',
              date: DateTime.now(),
              records: [],
            ),
      },

      home: FutureBuilder<void>(
        future: _bootstrap,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done ||
              !_triedAutoLogin) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, s) {
              if (s.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final user = s.data;
              if (user == null) return const LoginPage();

              // 🔹 Recuperar el rol desde Firestore
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (!snapshot.data!.exists) {
                    return const Scaffold(
                      body: Center(
                        child: Text(
                          'Tu cuenta no tiene rol asignado. Contacta con el administrador.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  final role = snapshot.data!['role'];
                  if (role == 'admin') {
                    return const AdminHomePage();
                  } else {
                    return const TeacherHomePage();
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
