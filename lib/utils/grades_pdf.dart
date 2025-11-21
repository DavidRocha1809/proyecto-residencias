import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models.dart';

class GradesPdf {
  GradesPdf._();

  static final _df = DateFormat("d 'de' MMM 'de' yyyy", 'es_MX');

  // ===============================================================
  // 🔹 Genera el resumen de calificaciones por alumno (PROMEDIOS)
  // ===============================================================
  static Future<void> exportSummaryByStudent({
    required String groupId,
    String? subject,
    String? groupName,
    required DateTime from,
    required DateTime to,
  }) async {
    print('📄 [GradesPdf] Iniciando exportSummaryByStudent()');
    print('➡️ groupId: $groupId | rango: ${from.toIso8601String()} - ${to.toIso8601String()}');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuario no autenticado.');
    final firestore = FirebaseFirestore.instance;

    // 🧭 1️⃣ Obtener alumnos del grupo
    final groupSnap = await firestore
        .collection('teachers')
        .doc(uid)
        .collection('assigned_groups')
        .doc(groupId)
        .get();

    if (!groupSnap.exists) throw Exception('No se encontró el grupo $groupId');
    final students = List<Map<String, dynamic>>.from(groupSnap['students'] ?? [])
        .map((s) => Student(
              id: s['matricula'] ?? '',
              name: s['name'] ?? '',
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    print('👩‍🎓 Total alumnos: ${students.length}');

    // Crear mapa base de calificaciones
    final map = {for (final s in students) s.id: _Stu(id: s.id, name: s.name)};

    // 🧭 2️⃣ Obtener actividades dentro del rango
    final actsSnap = await firestore
        .collection('teachers')
        .doc(uid)
        .collection('grades')
        .doc(groupId)
        .collection('activities')
        .get();

    final activities = actsSnap.docs.map((doc) {
      final data = doc.data();
      final dateStr = (data['date'] ?? '').toString();
      DateTime? d;
      try {
        d = DateFormat('yyyy-MM-dd').parse(dateStr);
      } catch (_) {}
      return {
        'id': doc.id,
        'activity': data['activity'] ?? '',
        'date': d,
        'grades': Map<String, dynamic>.from(data['grades'] ?? {}),
      };
    }).where((a) {
      final d = a['date'] as DateTime?;
      if (d == null) return false;
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();

    print('📚 Actividades dentro del rango: ${activities.length}');
    if (activities.isEmpty) throw Exception('No hay actividades en el rango seleccionado.');

    // 🧭 3️⃣ Calcular promedio por estudiante
    for (final act in activities) {
      final grades = Map<String, dynamic>.from(act['grades']);
      for (final sid in map.keys) {
        final score = double.tryParse(grades[sid]?.toString() ?? '');
        if (score != null) {
          map[sid]!.scores.add(score);
        }
      }
    }

    for (final s in map.values) {
      if (s.scores.isNotEmpty) {
        s.average = s.scores.reduce((a, b) => a + b) / s.scores.length;
      } else {
        s.average = 0.0;
      }
    }

    print('✅ Promedios calculados correctamente');

    // 🧭 4️⃣ Generar PDF
    await _sharePdf(
      title: 'Resumen de calificaciones por alumno',
      subtitle: '${subject ?? ''} ${groupName ?? ''}',
      header: const ['Matrícula', 'Nombre', 'Promedio'],
      rows: map.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
      filename:
          'resumen_calificaciones_${from.year}${from.month}${from.day}_${to.year}${to.month}${to.day}.pdf',
    );

    print('✅ PDF general generado correctamente');
  }

  // ===============================================================
  // 🔹 Genera PDF individual de una sola actividad
  // ===============================================================
  static Future<void> exportSingleActivity({
    required String groupId,
    required String activityId,
    required String activityName,
    String? subject,
    String? groupName,
  }) async {
    print('📄 [GradesPdf] Iniciando exportSingleActivity()');
    print('➡️ groupId: $groupId | activityId: $activityId | activityName: $activityName');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuario no autenticado.');
    print('👤 UID del docente: $uid');

    final firestore = FirebaseFirestore.instance;

    // 🧭 Obtener datos de la actividad
    print('📥 Buscando actividad en: /teachers/$uid/grades/$groupId/activities/$activityId');
    final docSnap = await firestore
        .collection('teachers')
        .doc(uid)
        .collection('grades')
        .doc(groupId)
        .collection('activities')
        .doc(activityId)
        .get();

    if (!docSnap.exists) {
      print('❌ No se encontró la actividad.');
      throw Exception('No se encontró la actividad.');
    }

    final data = docSnap.data()!;
    print('📦 Datos crudos de la actividad: $data');

    final grades = Map<String, dynamic>.from(data['grades'] ?? {});
    final dateStr = (data['date'] ?? '').toString();
    print('📅 Fecha cruda: $dateStr');
    print('🧮 Total de calificaciones registradas: ${grades.length}');

    // 🧭 Obtener lista de alumnos
    print('📥 Cargando alumnos del grupo: /teachers/$uid/assigned_groups/$groupId');
    final groupSnap = await firestore
        .collection('teachers')
        .doc(uid)
        .collection('assigned_groups')
        .doc(groupId)
        .get();

    if (!groupSnap.exists) {
      print('❌ No se encontró el grupo en assigned_groups.');
      throw Exception('No se encontró el grupo.');
    }

    final studentsRaw = groupSnap['students'];
    print('👩‍🎓 Total de alumnos encontrados: ${(studentsRaw as List?)?.length ?? 0}');
    final students = List<Map<String, dynamic>>.from(studentsRaw ?? [])
        .map((s) => Student(id: s['matricula'] ?? '', name: s['name'] ?? ''))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final rows = <_Stu>[];
    for (final s in students) {
      final raw = grades[s.id];
      final score = raw == null ? '' : raw.toString();
      rows.add(_Stu(id: s.id, name: s.name, score: score));
    }

    print('🧾 Mapeo de calificaciones preparado:');
    for (final r in rows) {
      print('   → ${r.id} | ${r.name} | ${r.score}');
    }

    // 🧭 Generar PDF
    try {
      final parsedDate =
          dateStr.isNotEmpty ? DateFormat('yyyy-MM-dd').parse(dateStr) : DateTime.now();
      final formattedDate = GradesPdf._df.format(parsedDate);
      print('📅 Fecha formateada: $formattedDate');

      await _shareSinglePdf(
        title: activityName, // ✅ nombre visible de la actividad
        subtitle: '${subject ?? ''} ${groupName ?? ''}\nFecha: $formattedDate',
        header: const ['Matrícula', 'Nombre', 'Calificación'],
        rows: rows,
        filename: 'calificaciones_${activityId}.pdf',
      );

      print('✅ PDF individual generado correctamente para $activityName');
    } catch (e) {
      print('💥 Error generando PDF: $e');
      rethrow;
    }
  }

  // ===============================================================
  // 🔹 PDF INDIVIDUAL — mismo diseño que el general
  // ===============================================================
  static Future<void> _shareSinglePdf({
    required String title,
    required String subtitle,
    required List<String> header,
    required List<_Stu> rows,
    required String filename,
  }) async {
    final logoBytes =
        (await rootBundle.load('assets/images/logo_cetis31.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Row(children: [
            pw.Container(width: 50, height: 50, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('CETIS 31',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                pw.Text('Calificaciones de actividad',
                    style: const pw.TextStyle(fontSize: 12)),
                pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11)),
                pw.Text('Actividad: $title',
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontStyle: pw.FontStyle.italic,
                        color: pdf.PdfColors.grey700)),
              ],
            )
          ]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            data: [
              header,
              for (final s in rows) [s.id, s.name, s.score],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: pdf.PdfColors.grey300),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  // ===============================================================
  // 🔹 PDF GENERAL DE PROMEDIOS
  // ===============================================================
  static Future<void> _sharePdf({
    required String title,
    required String subtitle,
    required List<String> header,
    required List<_Stu> rows,
    required String filename,
  }) async {
    final logoBytes =
        (await rootBundle.load('assets/images/logo_cetis31.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Row(children: [
            pw.Container(width: 50, height: 50, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('CETIS 31',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
              pw.Text(subtitle, style: const pw.TextStyle(fontSize: 11)),
            ])
          ]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            data: [
              header,
              for (final s in rows) [s.id, s.name, s.average.toStringAsFixed(2)],
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: pdf.PdfColors.grey300),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

    // ===============================================================
  // 🔹 Exportar reporte individual por alumno
  // ===============================================================
  static Future<void> exportStudentReport({
    required String groupId,
    required Student student,
    String? subject,
    String? groupName,
    required DateTime from,
    required DateTime to,
  }) async {
    print('📄 Generando reporte individual para ${student.name} (${student.id})');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Usuario no autenticado.');
    final firestore = FirebaseFirestore.instance;

    final actsSnap = await firestore
        .collection('teachers')
        .doc(uid)
        .collection('grades')
        .doc(groupId)
        .collection('activities')
        .get();

    final activities = actsSnap.docs.map((doc) {
      final data = doc.data();
      final dateStr = (data['date'] ?? '').toString();
      DateTime? d;
      try {
        d = DateFormat('yyyy-MM-dd').parse(dateStr);
      } catch (_) {}
      return {
        'activity': data['activity'] ?? '',
        'date': d,
        'grades': Map<String, dynamic>.from(data['grades'] ?? {}),
      };
    }).where((a) {
      final d = a['date'] as DateTime?;
      if (d == null) return false;
      return !d.isBefore(from) && !d.isAfter(to);
    }).toList();

    if (activities.isEmpty) throw Exception('No hay actividades en el rango.');

    // 🔹 Filtrar calificaciones del alumno
    final rows = <List<String>>[];
    double sum = 0;
    int count = 0;

    for (final a in activities) {
      final g = a['grades'][student.id];
      final score = g?.toString() ?? '';
      rows.add([
        DateFormat('dd/MM/yyyy').format(a['date']),
        a['activity'],
        score,
      ]);
      if (g != null && double.tryParse(g.toString()) != null) {
        sum += double.parse(g.toString());
        count++;
      }
    }

    final average = count > 0 ? (sum / count).toStringAsFixed(2) : '0.00';

    // 🔹 Generar PDF
    final logoBytes =
        (await rootBundle.load('assets/images/logo_cetis31.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Row(children: [
            pw.Container(width: 50, height: 50, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('CETIS 31',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Reporte individual de calificaciones',
                  style: const pw.TextStyle(fontSize: 12)),
              pw.Text('${subject ?? ''} ${groupName ?? ''}',
                  style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Alumno: ${student.name}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Matrícula: ${student.id}', style: const pw.TextStyle(fontSize: 11)),
            ])
          ]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: const ['Fecha', 'Actividad', 'Calificación'],
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(color: pdf.PdfColors.grey300),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Promedio general: $average',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'reporte_${student.name.replaceAll(' ', '_')}.pdf',
    );
  }

}

class _Stu {
  _Stu({
    required this.id,
    required this.name,
    this.score = '',
  });

  final String id;
  final String name;
  final String score; // usado para PDFs individuales
  final List<double> scores = [];
  double average = 0.0;
}
