import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'models.dart';
import 'pages/login_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/attendance_page.dart';
import 'pages/reports_page.dart';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart' as pp;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Hive: carpeta de documentos de la app y box local para sesiones
  final dir = await pp.getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);
  await Hive.openBox('sessions');

  // Locale por defecto en español (México)
  await initializeDateFormatting('es_MX');
  Intl.defaultLocale = 'es_MX';

  // Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const AsistenciasApp());
}

class AsistenciasApp extends StatelessWidget {
  const AsistenciasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistema de Asistencia - CETIS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFFB71C1C),
      ),

      // Localización para pickers, labels, formateo, etc.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'MX'), Locale('en', 'US')],
      locale: const Locale('es', 'MX'),

      // Ruta inicial
      initialRoute: LoginPage.route,

      // Rutas simples (sin argumentos)
      routes: {
        LoginPage.route: (_) => const LoginPage(),
        DashboardPage.route: (_) => const DashboardPage(teacherName: 'Docente'),
      },

      // Rutas con argumentos
      onGenerateRoute: (settings) {
        if (settings.name == AttendancePage.route) {
          final group = settings.arguments as GroupClass;
          return MaterialPageRoute(
            builder:
                (_) => AttendancePage(
                  groupClass: group,
                  initialDate: DateTime.now(),
                ),
          );
        }
        if (settings.name == ReportsPage.route) {
          // IMPORTANTE: usar initialGroup (no 'groupClass')
          final group = settings.arguments as GroupClass?;
          return MaterialPageRoute(
            builder: (_) => ReportsPage(initialGroup: group),
          );
        }
        return null;
      },
    );
  }
}
