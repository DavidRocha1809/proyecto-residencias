import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';

import '../local_groups.dart' as LG;
import '../services/attendance_service.dart';

class AttendancePdf {
  AttendancePdf._();

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  /// Exporta resumen por **alumno** (A=presentes, R=retardos, F=faltas).
  static Future<void> exportSummaryByStudent({
    required String groupId,
    String? subject,
    String? groupName,
    required DateTime from,
    required DateTime to,
  }) async {
    // 1) Alumnos locales (para nombres y matrículas)
    final students = await LG.LocalGroups.listStudents(groupId: groupId);
    // index por matrícula
    final map = <String, _Stu>{
      for (final s in students) s.id: _Stu(id: s.id, name: s.name),
    };

    // 2) Todas las sesiones del rango
    final sessions = await AttendanceService.instance.listSessionsDetailed(
      groupId: groupId,
      dateFrom: from,
      dateTo: to,
    );

    // 3) Acumular A/R/F por alumno
    for (final sess in sessions) {
      final recs = (sess['records'] as List?) ?? const [];
      for (final r in recs) {
        final sid = (r is Map && r['studentId'] != null)
            ? r['studentId'].toString()
            : '';
        if (!map.containsKey(sid)) continue;
        final st = (r['status'] ?? '').toString();
        switch (st) {
          case 'present':
            map[sid]!.a++;
            break;
          case 'late':
            map[sid]!.r++;
            break;
          case 'absent':
            map[sid]!.f++;
            break;
        }
      }
    }

    final rowsSorted = map.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // 4) PDF
    final logoBytes =
        (await rootBundle.load('assets/images/logo_cetis31.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);

    final df = DateFormat("d 'de' MMM 'de' yyyy", 'es_MX');
    final doc = pw.Document();

    // Encabezado
    final header = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          width: 48,
          height: 48,
          child: pw.Image(logo, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 12),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Sistema CETIS 31',
                style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text('Historial de asistencia (resumen por alumno)',
                style: const pw.TextStyle(fontSize: 12)),
          ],
        ),
      ],
    );

    final subtitle = pw.Text(
      [
        if ((subject ?? '').isNotEmpty) subject!,
        if ((groupName ?? '').isNotEmpty) groupName!,
        'Periodo: ${df.format(from)} — ${df.format(to)}',
      ].where((e) => e.isNotEmpty).join('   •   '),
      style: const pw.TextStyle(fontSize: 11),
    );

    // Tabla
    final tableData = <List<String>>[
      <String>['Matrícula', 'Nombre del alumno', 'A', 'R', 'F'],
      for (final s in rowsSorted)
        <String>[s.id, s.name, '${s.a}', '${s.r}', '${s.f}'],
    ];

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          header,
          pw.SizedBox(height: 8),
          subtitle,
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            data: tableData,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(
              color: pdf.PdfColors.grey300,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            border: null,
          ),
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Total de alumnos: ${rowsSorted.length}',
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );

    final Uint8List bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'reporte_asistencias_alumnos_${_ymd(from)}_${_ymd(to)}.pdf',
    );
  }
}

class _Stu {
  _Stu({required this.id, required this.name});
  final String id;
  final String name;
  int a = 0; // asistencias (present)
  int r = 0; // retardos
  int f = 0; // faltas (absent)
}
