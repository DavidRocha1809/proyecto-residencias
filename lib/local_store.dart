import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';
import 'local_groups.dart' as LG;
import 'services/attendance_service.dart';

class LocalStore {
  static const _boxName = 'sessions';

  // ================== Hive helpers ==================
  static Future<Box> _ensureBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  static String _key(String classId, DateTime date) {
    final d = DateFormat('yyyy-MM-dd').format(date);
    return 'session::$classId::$d';
  }

  static String _fmt(TimeOfDay? t) =>
      t == null
          ? '--:--'
          : '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

  static String _statusText(String status) {
    switch (status) {
      case 'present':
        return 'Presente';
      case 'late':
        return 'Retardo';
      case 'absent':
        return 'Ausente';
      default:
        return 'Sin marcar';
    }
  }

  // ================== Guardar local ==================
  static Future<void> saveTodaySession({
    required GroupClass groupClass,
    required DateTime date,
    required List<Student> students,
  }) async {
    final box = await _ensureBox();
    final key = _key(LG.groupKeyOf(groupClass), date);

    final records = students
        .map((s) => <String, dynamic>{
              'studentId': s.id,
              'name': s.name,
              'status': s.status.name,
            })
        .toList();

    final value = <String, dynamic>{
      'classId': LG.groupKeyOf(groupClass),
      'subject': groupClass.subject,
      'groupName': groupClass.groupName,
      'start': _fmt(groupClass.start),
      'end': _fmt(groupClass.end),
      'date': DateFormat('yyyy-MM-dd').format(date),
      'records': records,
      'savedAt': DateTime.now().toIso8601String(),
    };

    await box.put(key, value);
  }

  static Map<String, dynamic>? getSession(String classId, DateTime date) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final box = Hive.box(_boxName);
    final v = box.get(_key(classId, date));
    return (v is Map) ? Map<String, dynamic>.from(v as Map) : null;
  }

  static Map<String, int> dailySummary(String classId, DateTime date) {
    final data = getSession(classId, date);
    if (data == null) return {'present': 0, 'late': 0, 'absent': 0, 'total': 0};

    final recsRaw = (data['records'] as List?) ?? const [];
    final recs = recsRaw
        .map<Map<String, dynamic>>(
          (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
        )
        .toList();

    final present = recs.where((r) => r['status'] == 'present').length;
    final late = recs.where((r) => r['status'] == 'late').length;
    final absent = recs.where((r) => r['status'] == 'absent').length;
    final total = recs.length;
    return {'present': present, 'late': late, 'absent': absent, 'total': total};
  }

  // ================== PDF inteligente (local → cloud) ==================
  static Future<void> exportSessionPdfSmart({
    required String groupId,
    required DateTime date,
    String? subject,
  }) async {
    // 1) intenta local
    Map<String, dynamic>? data = getSession(groupId, date);

    // 2) si no hay local, intenta Firestore
    if (data == null) {
      final cloud = await AttendanceService.instance.getSessionByGroupAndDate(
        groupId: groupId,
        date: date,
      );

      if (cloud != null) {
        final records = ((cloud['records'] as List?) ?? const [])
            .map<Map<String, dynamic>>((e) =>
                e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
            .toList();

        data = <String, dynamic>{
          'classId': cloud['groupId'] ?? groupId,
          'subject': cloud['subject'] ?? subject ?? '',
          'groupName': cloud['groupName'] ?? '',
          'start': (cloud['start'] ?? '--:--').toString(),
          'end': (cloud['end'] ?? '--:--').toString(),
          'date':
              (cloud['date'] ?? DateFormat('yyyy-MM-dd').format(date)).toString(),
          'records': records,
        };
      }
    }

    if (data == null) {
      throw Exception('No hay lista guardada para ese día.');
    }

    // ¡a partir de aquí usa SIEMPRE una variable no-nula!
    final d = data; // d es Map<String, dynamic> (no nullable)
    final recs = ((d['records'] as List?) ?? const [])
        .map<Map<String, dynamic>>(
          (e) => e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{},
        )
        .toList();

    final doc = pw.Document();
    final df = DateFormat("EEEE d 'de' MMMM 'de' yyyy", 'es_MX');

    final dateStr = (d['date']?.toString() ?? DateFormat('yyyy-MM-dd').format(date));
    final parsed = DateTime.tryParse(dateStr) ?? date;

    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Lista de Asistencia',
                  style:
                      pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(df.format(parsed), style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
          ),
          pw.Text(
            '${(d['subject'] ?? '').toString()} — ${(d['groupName'] ?? '').toString()}',
            style: pw.TextStyle(fontSize: 16),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Horario: ${(d['start'] ?? '--:--').toString()} - ${(d['end'] ?? '--:--').toString()}'),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: const ['#', 'ID', 'Nombre', 'Estado'],
            data: List<List<String>>.generate(recs.length, (i) {
              final r = recs[i];
              return [
                '${i + 1}',
                (r['studentId'] ?? '').toString(),
                (r['name'] ?? '').toString(),
                _statusText((r['status'] ?? '').toString()),
              ];
            }),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: const {
              0: pw.Alignment.centerRight,
              1: pw.Alignment.center,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
            },
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'asistencia_${groupId}_${DateFormat('yyyyMMdd').format(parsed)}.pdf',
    );
  }

  // ================== PDF por rango ==================
  static Future<void> exportPeriodPdf({
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> rows,
    String? titulo,
  }) async {
    if (rows.isEmpty) {
      throw Exception('No hay registros para exportar.');
    }

    rows.sort((a, b) {
      final da =
          DateTime.tryParse((a['date'] ?? a['id']).toString()) ?? DateTime.now();
      final db =
          DateTime.tryParse((b['date'] ?? b['id']).toString()) ?? DateTime.now();
      return da.compareTo(db);
    });

    int tp = 0, tl = 0, ta = 0, tt = 0;
    for (final r in rows) {
      tp += (r['present'] ?? r['presentCount'] ?? 0) as int;
      tl += (r['late'] ?? 0) as int;
      ta += (r['absent'] ?? 0) as int;
      tt += (r['total'] ??
              ((r['present'] ?? 0) + (r['late'] ?? 0) + (r['absent'] ?? 0)))
          as int;
    }
    final prom = tt == 0 ? 0 : ((tp / tt) * 100).round();

    final dfTitle = DateFormat("d 'de' MMMM 'de' yyyy", 'es_MX');
    final dfRow = DateFormat('yyyy-MM-dd');

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(
            level: 0,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  titulo ?? 'Reporte de Asistencias',
                  style:
                      pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Periodo: ${dfTitle.format(from)} — ${dfTitle.format(to)}',
                  style: pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Resumen global • Presentes: $tp • Retardos: $tl • Ausentes: $ta • Total: $tt • Promedio: $prom%',
                  style: pw.TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: const ['Fecha', 'Materia', 'Grupo', 'P', 'R', 'A', 'Total'],
            data: rows.map<List<String>>((r) {
              final dt = DateTime.tryParse((r['date'] ?? r['id']).toString()) ??
                  DateTime.now();
              final subj = (r['subject'] ?? '').toString();
              final gname = (r['groupName'] ?? '').toString();
              final p = (r['present'] ?? r['presentCount'] ?? 0).toString();
              final l = (r['late'] ?? 0).toString();
              final a = (r['absent'] ?? 0).toString();
              final tot =
                  (r['total'] ??
                          ((r['present'] ?? 0) +
                              (r['late'] ?? 0) +
                              (r['absent'] ?? 0)))
                      .toString();
              return [dfRow.format(dt), subj, gname, p, l, a, tot];
            }).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignments: const {
              0: pw.Alignment.center,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
            },
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'reporte_asistencias_${DateFormat('yyyyMMdd').format(from)}_${DateFormat('yyyyMMdd').format(to)}.pdf',
    );
  }
}
