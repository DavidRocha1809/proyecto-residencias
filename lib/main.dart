import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'firebase_options.dart';
import 'pages/dashboard_page.dart';

/// Estado simple para mostrar advertencias de autenticación en UI
class AuthGuard {
  static bool authOk = false;
  static String? authWarning;
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0) Localización para Intl (necesaria para DateFormat con 'es_MX')
  Intl.defaultLocale = 'es_MX';
  await initializeDateFormatting(
    'es_MX',
  ); // <-- clave para evitar LocaleDataException

  // 1) Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2) Hive
  await Hive.initFlutter();

  // 3) Auth: intenta anónimo pero sin crashear si está deshabilitado
  try {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    AuthGuard.authOk = true;
  } on FirebaseAuthException catch (e) {
    AuthGuard.authOk = false;
    if (e.code == 'operation-not-allowed' ||
        e.code == 'admin-restricted-operation') {
      AuthGuard.authWarning =
          'No se pudo iniciar sesión anónima. Habilita "Anonymous" en Firebase Auth o usa otro proveedor.';
    } else {
      AuthGuard.authWarning = 'No se pudo autenticar: ${e.code}';
    }
  } catch (e) {
    AuthGuard.authOk = false;
    AuthGuard.authWarning = 'Error de autenticación: $e';
  }
}

void main() async {
  await _bootstrap();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sistema CETIS 31',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7A3E3E),
        useMaterial3: true,
      ),
      // Opcional: declarar locales soportados
      supportedLocales: const [Locale('es', 'MX'), Locale('es'), Locale('en')],
      locale: const Locale('es', 'MX'),
      home: DashboardPage(
        teacherName: 'Docente',
        authWarning: AuthGuard.authWarning,
      ),
    );
  }
}
