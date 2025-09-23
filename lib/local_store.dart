import 'dart:typed_data';

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

  // ------ utils ------
  static Future<Box> _ensureBox() async {
    // Si Hive no se ha inicializado por cualquier motivo, lo iniciamos aquí
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox(_boxName);
      }
      return Hive.box(_boxName);
    } on HiveError {
      // Intento de “autoinit” seguro
      await Hive.initFlutter();
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox(_boxName);
      }
      return Hive.box(_boxName);
    }
  }

  static String _key(String classId, DateTime date) {
    final d = DateFormat('yyyy-MM-dd').format(date);
    return 'session::$classId::$d';
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

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
  // -------------------

  static Future<void> saveTodaySession({
    required GroupClass groupClass,
    required DateTime date,
    required List<Student> students,
  }) async {
    final box = await _ensureBox();
    final key = _key(LG.groupKeyOf(groupClass), date);

    final records =
        students
            .map(
              (s) => {
                'studentId': s.id,
                'name': s.name,
                'status': s.status.name,
              },
            )
            .toList();

    final value = {
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

  static Future<bool> removeSession({
    required String classId,
    required DateTime date,
  }) async {
    final box = await _ensureBox();
    final k = _key(classId, date);
    if (box.containsKey(k)) {
      await box.delete(k);
      return true;
    }
    return false;
  }

  static Map<String, dynamic>? getSession(String classId, DateTime date) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final box = Hive.box(_boxName);
    final v = box.get(_key(classId, date));
    return (v is Map) ? v.cast<String, dynamic>() : null;
  }

  static Map<String, int> dailySummary(String classId, DateTime date) {
    final data = getSession(classId, date);
    if (data == null) return {'present': 0, 'late': 0, 'absent': 0, 'total': 0};

    final recs = (data['records'] as List).cast<Map>();
    final present = recs.where((r) => r['status'] == 'present').length;
    final late = recs.where((r) => r['status'] == 'late').length;
    final absent = recs.where((r) => r['status'] == 'absent').length;
    final total = recs.length;
    return {'present': present, 'late': late, 'absent': absent, 'total': total};
  }

  // ---------- PDF ----------
  static Future<void> exportTodayPdf(
    GroupClass groupClass,
    DateTime date,
  ) async {
    final data = getSession(LG.groupKeyOf(groupClass), date);
    if (data == null) throw Exception('No hay lista guardada para hoy.');
    final recs = (data['records'] as List).cast<Map>();

    final bytes = await _buildPdf(groupClass, date, recs);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'asistencia_${LG.groupKeyOf(groupClass)}_${DateFormat('yyyyMMdd').format(date)}.pdf',
    );
  }

  /// Fallback: si no hay local, lee Firestore en la ruta /teachers/{uid}/...
  static Future<void> exportTodayPdfFallback(
    GroupClass groupClass,
    DateTime date,
  ) async {
    final local = getSession(LG.groupKeyOf(groupClass), date);
    if (local != null) {
      final recs = (local['records'] as List).cast<Map>();
      final bytes = await _buildPdf(groupClass, date, recs);
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'asistencia_${LG.groupKeyOf(groupClass)}_${DateFormat('yyyyMMdd').format(date)}.pdf',
      );
      return;
    }

    final list = await AttendanceService.instance.listSessions(
      groupId: LG.groupKeyOf(groupClass),
      limit: 1,
      dateFrom: date,
      dateTo: date,
    );
    if (list.isEmpty) {
      final ymd = DateFormat('yyyy-MM-dd').format(date);
      throw Exception(
        'No hay sesión guardada para $ymd ni en local ni en Firestore.',
      );
    }

    final raw = list.first;
    final remoteRecs = (raw['students'] as List?)?.cast<Map>() ?? const <Map>[];
    final bytes = await _buildPdf(groupClass, date, remoteRecs);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'asistencia_${LG.groupKeyOf(groupClass)}_${DateFormat('yyyyMMdd').format(date)}.pdf',
    );
  }

  static Future<void> exportPdfFromRecords({
    required GroupClass groupClass,
    required DateTime date,
    required List<Map<String, dynamic>> records,
  }) async {
    final recs =
        records
            .map(
              (r) => {
                'studentId':
                    (r['studentId'] ?? r['matricula'] ?? '').toString(),
                'name': (r['name'] ?? '').toString(),
                'status': (r['status'] ?? 'none').toString(),
              },
            )
            .toList();

    final bytes = await _buildPdf(groupClass, date, recs);
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'asistencia_${LG.groupKeyOf(groupClass)}_${DateFormat('yyyyMMdd').format(date)}.pdf',
    );
  }

  static Future<Uint8List> _buildPdf(
    GroupClass groupClass,
    DateTime date,
    List<Map> recs,
  ) async {
    final doc = pw.Document();
    final df = DateFormat("EEEE d 'de' MMMM 'de' yyyy", 'es_MX');

    doc.addPage(
      pw.MultiPage(
        build:
            (_) => [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Lista de Asistencia',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      df.format(date),
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              pw.Text(
                '${groupClass.subject} — ${groupClass.groupName}',
                style: pw.TextStyle(fontSize: 16),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Horario: ${_fmt(groupClass.start)} - ${_fmt(groupClass.end)}',
              ),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                headers: const ['#', 'ID', 'Nombre', 'Estado'],
                data: List.generate(recs.length, (i) {
                  final r = recs[i];
                  return [
                    '${i + 1}',
                    (r['studentId'] ?? '').toString(),
                    (r['name'] ?? '').toString(),
                    _statusText((r['status'] ?? 'none').toString()),
                  ];
                }),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellAlignments: {
                  0: pw.Alignment.centerRight,
                  1: pw.Alignment.center,
                  2: pw.Alignment.centerLeft,
                  3: pw.Alignment.center,
                },
              ),
            ],
      ),
    );

    return Uint8List.fromList(await doc.save());
  }
}
