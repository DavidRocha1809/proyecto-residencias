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

  // ---------- PDF GENERAL (rango) RESUMEN POR ALUMNO ----------
  static Future<void> exportSummaryByStudent({
    required String groupId,
    String? subject,
    String? groupName,
    required DateTime from,
    required DateTime to,
  }) async {
    final students = await LG.LocalGroups.listStudents(groupId: groupId);
    final map = <String, _Stu>{
      for (final s in students) s.id: _Stu(id: s.id, name: s.name),
    };

    final sessions = await AttendanceService.instance.listSessionsDetailed(
      groupId: groupId,
      dateFrom: from,
      dateTo: to,
    );

    for (final sess in sessions) {
      final recs = (sess['records'] as List?) ?? const [];
      for (final r in recs) {
        final sid = (r is Map && r['studentId'] != null) ? '${r['studentId']}' : '';
        if (!map.containsKey(sid)) continue;
        final st = '${r['status'] ?? ''}';
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

    await _sharePdf(
      title: 'Historial de asistencia (resumen por alumno)',
      subtitleParts: [
        if ((subject ?? '').isNotEmpty) subject!,
        if ((groupName ?? '').isNotEmpty) groupName!,
        'Periodo: ${_df.format(from)} — ${_df.format(to)}',
      ],
      header: const ['Matrícula', 'Nombre del alumno', 'A', 'R', 'F'],
      rows: map.values
          .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      rowBuilder: (s) => [s.id, s.name, '${s.a}', '${s.r}', '${s.f}'],
      filename: 'reporte_asistencias_alumnos_${_ymd(from)}_${_ymd(to)}.pdf',
    );
  }

  // ---------- PDF DE UN DÍA (por alumno) ----------
  static Future<void> exportSingleSessionByStudent({
    required String groupId,
    String? subject,
    String? groupName,
    required DateTime date,
  }) async {
    final students = await LG.LocalGroups.listStudents(groupId: groupId);
    final map = <String, _Stu>{
      for (final s in students) s.id: _Stu(id: s.id, name: s.name),
    };

    final sess = await AttendanceService.instance.getSessionByGroupAndDate(
      groupId: groupId,
      date: date,
    );

    final recs = (sess?['records'] as List?) ?? const [];
    for (final r in recs) {
      final sid = (r is Map && r['studentId'] != null) ? '${r['studentId']}' : '';
      if (!map.containsKey(sid)) continue;
      final st = '${r['status'] ?? ''}';
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

    await _sharePdf(
      title: 'Asistencia del día (${_df.format(date)})',
      subtitleParts: [
        if ((subject ?? '').isNotEmpty) subject!,
        if ((groupName ?? '').isNotEmpty) groupName!,
      ],
      header: const ['Matrícula', 'Nombre del alumno', 'A', 'R', 'F'],
      rows: map.values
          .toList()
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      rowBuilder: (s) => [s.id, s.name, '${s.a}', '${s.r}', '${s.f}'],
      filename: 'asistencia_${_ymd(date)}.pdf',
    );
  }

  // ---------- Helper común para armar el PDF con logo ----------
  static final _df = DateFormat("d 'de' MMM 'de' yyyy", 'es_MX');

  static Future<void> _sharePdf({
    required String title,
    required List<String> subtitleParts,
    required List<String> header,
    required List<_Stu> rows,
    required List<String> Function(_Stu) rowBuilder,
    required String filename,
  }) async {
    final logoBytes =
        (await rootBundle.load('assets/images/logo_cetis31.png')).buffer.asUint8List();
    final logo = pw.MemoryImage(logoBytes);

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (_) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(width: 48, height: 48, child: pw.Image(logo, fit: pw.BoxFit.contain)),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Asistenciaue CETIS 31',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            subtitleParts.where((e) => e.isNotEmpty).join('   •   '),
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            data: <List<String>>[
              header,
              for (final s in rows) rowBuilder(s),
            ],
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
            child: pw.Text('Total de alumnos: ${rows.length}',
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ),
    );

    final Uint8List bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: filename);
  }
}

class _Stu {
  _Stu({required this.id, required this.name});
  final String id;
  final String name;
  int a = 0; // present
  int r = 0; // late
  int f = 0; // absent
}
