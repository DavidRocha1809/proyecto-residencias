import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';

class AttendancePdf {
  AttendancePdf._();

  // ===============================================================
  // 🔹 Genera el resumen de asistencia por alumno (versión reactiva)
  // ===============================================================
  static Future<void> exportSummaryByStudent({
  required String groupId,
  String? subject,
  String? groupName,
  required DateTime from,
  required DateTime to,
}) async {
  print('📄 [AttendancePdf] Iniciando exportSummaryByStudent()');
  print('➡️ groupId: $groupId | rango: $from - $to');
  print('🧾 Nombre recibido: ${groupName ?? '(sin nombre)'}');

  final visualName = groupName ?? groupId;

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('Usuario no autenticado.');

  final firestore = FirebaseFirestore.instance;

  // 🔹 Obtener lista de alumnos
  // 🔹 Obtener alumnos desde la última sesión del grupo en "attendance"
print('👩‍🎓 Buscando alumnos desde attendance/$groupId...');

final attendanceRef = firestore
    .collection('teachers')
    .doc(uid)
    .collection('attendance');

final sessionDocs = await attendanceRef
    .where('groupName', isEqualTo: groupName ?? groupId)
    .get();



if (sessionDocs.docs.isEmpty) {
  print('⚠️ No se encontró ninguna sesión para $groupId.');
} else {
  print('✅ Sesión más reciente encontrada: ${sessionDocs.docs.first.id}');
}

final sessionData = sessionDocs.docs.isNotEmpty
    ? sessionDocs.docs.first.data()
    : {};

final records = List<Map<String, dynamic>>.from(sessionData['records'] ?? []);

final students = records
    .map((r) => _Stu(
          id: r['studentId'] ?? '',
          name: r['name'] ?? '',
        ))
    .toList();

print('👩‍🎓 Total alumnos encontrados en la sesión: ${students.length}');


  // 🔹 Crear base por estudiante
  final map = {for (final s in students) s.id: _Stu(id: s.id, name: s.name)};

  // 🔹 Leer sesiones de asistencia del rango (en tiempo real)
    print('📦 Leyendo sesiones del rango...');
  final attendanceSessionsRef =
      firestore.collection('teachers').doc(uid).collection('attendance');
  final sessionsSnap = await attendanceSessionsRef.get();


  print('📚 Total sesiones encontradas: ${sessionsSnap.docs.length}');

  // 🔹 Filtrar sesiones del grupo y rango de fechas
  final sessions = sessionsSnap.docs.map((doc) {
    final data = doc.data();
    final date = data['date'];
    final groupNameDoc = data['groupName'] ?? '';
    return {
      'id': doc.id,
      'date': date,
      'groupName': groupNameDoc,
      'records': data['records'] ?? [],
    };
  }).where((s) {
    final d = _safeParseDate(s['date']);
    final insideRange =
        !d.isBefore(from) && !d.isAfter(to) && (s['groupName'] ?? '') == groupName;
    print(
        '🔍 Revisando sesión ${s['id']} => fecha=$d | dentro del rango=$insideRange');
    return insideRange;
  }).toList();

  print('🎯 Sesiones filtradas finales: ${sessions.length}');

  if (sessions.isEmpty) {
    print('⚠️ No se encontraron sesiones para este grupo/rango.');
    throw Exception('No se encontraron registros de asistencia en el rango.');
  }
    // 🔹 Contar asistencias, retardos y faltas
  print('🧮 Contando asistencias, retardos y faltas...');
  for (final s in sessions) {
    final recs = List<Map<String, dynamic>>.from(s['records'] ?? []);
    for (final r in recs) {
      final id = r['studentId'];
      final status = (r['status'] ?? '').toString();
      if (!map.containsKey(id)) continue;

      switch (status) {
        case 'present':
          map[id]!.present++;
          break;
        case 'late':
          map[id]!.late++;
          break;
        case 'absent':
          map[id]!.absent++;
          break;
      }
    }
  }

  print('✅ Conteo completado para ${map.length} alumnos');


    // 🔹 Combinar el nombre visual (si existe)
  final fullName = (groupName != null && groupName.isNotEmpty)
      ? '$groupName – $groupId'
      : groupId;
  print('🖨️ Generando PDF con título: "$fullName"');

  await _sharePdf(
    title: 'Resumen de asistencia por alumno',
    subtitle: fullName,
    header: const ['Matrícula', 'Nombre', 'A', 'R', 'F'],
    rows: map.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
    filename:
        'resumen_asistencia_${from.year}${from.month}${from.day}_${to.year}${to.month}${to.day}.pdf',
  );

  print('✅ PDF generado correctamente.');
}



  // ===============================================================
// 🔹 Genera reporte PDF individual por alumno (versión reactiva)
// ===============================================================
static Future<void> exportStudentReport({
  required String groupId,
  required Student student,
  String? subject,
  String? groupName,
  required DateTime from,
  required DateTime to,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) throw Exception('Usuario no autenticado.');

  print('📄 [AttendancePdf] Generando PDF individual para ${student.name}');
  print('➡️ groupId: $groupId | rango: ${from.toIso8601String()} - ${to.toIso8601String()}');

  final firestore = FirebaseFirestore.instance;

  // 🧭 1️⃣ Obtener todas las sesiones actualizadas
  final attendanceRef = firestore.collection('teachers').doc(uid).collection('attendance');
  final allDocs = await attendanceRef.snapshots().first;
  print('📦 Total documentos en colección: ${allDocs.docs.length}');

  // 🧭 2️⃣ Filtrar sesiones del grupo y rango
  final sessions = allDocs.docs.where((doc) {
    final id = doc.id;
    final data = doc.data();
    final d = _safeParseDate(data['date']);
    final insideGroup = id.contains(groupId);
    final insideRange = !d.isBefore(from) && !d.isAfter(to);
    return insideGroup && insideRange;
  }).toList();

  if (sessions.isEmpty) {
    print('⚠️ No se encontraron sesiones dentro del rango.');
    throw Exception('No se encontraron registros en el rango.');
  }

  print('✅ ${sessions.length} sesiones encontradas dentro del rango.');

  // 🧾 3️⃣ Procesar asistencias del alumno
  final records = <Map<String, dynamic>>[];
  for (final s in sessions) {
    final data = s.data();
    final date = _safeParseDate(data['date']);
    final recs = List<Map<String, dynamic>>.from(data['records'] ?? []);
    final r = recs.firstWhere(
      (x) => x['studentId'] == student.id,
      orElse: () => {},
    );
    if (r.isNotEmpty) {
      records.add({
        'date': date,
        'status': r['status'] ?? 'none',
        'start': data['start'] ?? '',
        'end': data['end'] ?? '',
      });
    }
  }

  if (records.isEmpty) {
    print('⚠️ El alumno ${student.name} no tiene registros en el rango.');
    throw Exception('El alumno no tiene registros en el rango.');
  }

  print('📋 ${records.length} registros encontrados para ${student.name}');

  // 🧭 4️⃣ Generar PDF individual
  final doc = pw.Document();
  final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
  final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

  final df = DateFormat('d/MM/yyyy', 'es_MX');

  doc.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Row(children: [
          pw.Container(width: 50, height: 50, child: pw.Image(logo)),
          pw.SizedBox(width: 10),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('CETIS 31',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Reporte individual de asistencias', style: pw.TextStyle(fontSize: 12)),
            pw.Text('${student.name} — ${student.id}', style: pw.TextStyle(fontSize: 11)),
            pw.Text('${subject ?? ''}  ${groupName ?? ''}', style: pw.TextStyle(fontSize: 11)),
          ])
        ]),
        pw.SizedBox(height: 15),
        pw.TableHelper.fromTextArray(
          headers: ['Fecha', 'Entrada', 'Salida', 'Estado'],
          data: [
            for (final r in records)
              [
                df.format(r['date']),
                r['start'] ?? '',
                r['end'] ?? '',
                (r['status'] ?? '').toString(),
              ],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 10),
          border: pw.TableBorder.all(color: pdf.PdfColors.grey300),
        ),
      ],
    ),
  );

  final filename =
      'asistencia_${student.id}_${from.year}${from.month}${from.day}_${to.year}${to.month}${to.day}.pdf';
  final bytes = await doc.save();

  await Printing.sharePdf(bytes: bytes, filename: filename);
  print('🎉 PDF individual generado correctamente para ${student.name}');
}


  // ===============================================================
  // 🔹 Generador del PDF
  // ===============================================================
  static Future<void> _sharePdf({
    required String title,
    required String subtitle,
    required List<String> header,
    required List<_Stu> rows,
    required String filename,
  }) async {
    final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Row(children: [
            pw.Container(width: 50, height: 50, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('CETIS 31', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text(title, style: pw.TextStyle(fontSize: 12)),
                  pw.Text(subtitle ?? '', style: pw.TextStyle(fontSize: 11)),
                ])
          ]),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: header,
            data: [
              for (final s in rows)
                [s.id, s.name, '${s.present}', '${s.late}', '${s.absent}']
            ],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            border: pw.TableBorder.all(color: pdf.PdfColors.grey300),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }

  // ===============================================================
  // 🔹 Conversión segura de fechas (Firestore → DateTime)
  // ===============================================================
  static DateTime _safeParseDate(dynamic value) {
    if (value == null) return DateTime(0);
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return DateTime(0);
  }
}

// ===============================================================
// 🔹 Clase auxiliar interna (estructura para el conteo por alumno)
// ===============================================================
class _Stu {
  final String id;
  final String name;
  int present = 0;
  int late = 0;
  int absent = 0;

  _Stu({required this.id, required this.name});
}
