import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';
import 'local_groups.dart' as LG; // alias para groupKeyOf

class LocalStore {
  static const _boxName = 'sessions';

  // --- utilidades internas ---
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
  // --- fin utilidades internas ---

  /// Guarda la lista del día para una clase (en almacenamiento local)
  /// Usa la lista de estudiantes ACTUALIZADA que viene de la pantalla.
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

  /// Obtiene la sesión del día (o null)
  static Map<String, dynamic>? getSession(String classId, DateTime date) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final box = Hive.box(_boxName);
    final v = box.get(_key(classId, date));
    return (v is Map) ? v.cast<String, dynamic>() : null;
  }

  /// Resumen del día para reportes
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

  /// Exporta la sesión del día (detallado por alumnos) usando GroupClass.
  static Future<void> exportTodayPdf(
    GroupClass groupClass,
    DateTime date,
  ) async {
    final data = getSession(LG.groupKeyOf(groupClass), date);
    if (data == null) throw Exception('No hay lista guardada para hoy.');
    final recs = (data['records'] as List).cast<Map>();

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
                headers: ['#', 'ID', 'Nombre', 'Estado'],
                data: List.generate(recs.length, (i) {
                  final r = recs[i];
                  return [
                    '${i + 1}',
                    r['studentId'],
                    r['name'],
                    _statusText(r['status']),
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
              pw.SizedBox(height: 12),
              () {
                final s = dailySummary(LG.groupKeyOf(groupClass), date);
                final avg =
                    s['total'] == 0
                        ? 0
                        : ((s['present']! / s['total']!) * 100).round();
                return pw.Text(
                  'Resumen: Presentes ${s['present']}, Retardos ${s['late']}, Ausentes ${s['absent']}, '
                  'Total ${s['total']} — Promedio $avg%',
                );
              }(),
            ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'asistencia_${LG.groupKeyOf(groupClass)}_${DateFormat('yyyyMMdd').format(date)}.pdf',
    );
  }

  /// NUEVO: Exporta la lista detallada (alumnos) de una sesión por groupId y fecha.
  /// Ideal para el botón "PDF (este día)" en el Historial.
  static Future<void> exportSessionPdfByGroup({
    required String groupId,
    required DateTime date,
    String? subject,
    String? groupName,
    String? start, // "HH:mm"
    String? end, // "HH:mm"
  }) async {
    final data = getSession(groupId, date);
    if (data == null) {
      throw Exception('No hay lista guardada para ese día.');
    }

    final recs = (data['records'] as List).cast<Map>();

    // Si no pasan metadata, usa lo que quedó guardado en la sesión
    final _subject = subject ?? (data['subject'] as String? ?? '');
    final _group = groupName ?? (data['groupName'] as String? ?? '');
    final _start = start ?? (data['start'] as String? ?? '');
    final _end = end ?? (data['end'] as String? ?? '');

    // Conteos
    final present = recs.where((r) => r['status'] == 'present').length;
    final late = recs.where((r) => r['status'] == 'late').length;
    final absent = recs.where((r) => r['status'] == 'absent').length;
    final total = recs.length;
    final prom = total == 0 ? 0 : ((present / total) * 100).round();

    final doc = pw.Document();
    final dfTitle = DateFormat("EEEE d 'de' MMMM 'de' yyyy", 'es_MX');

    doc.addPage(
      pw.MultiPage(
        build:
            (_) => [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Lista de asistencia',
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          [
                            if (_subject.isNotEmpty) _subject,
                            if (_group.isNotEmpty) '• $_group',
                          ].join(' '),
                          style: pw.TextStyle(fontSize: 13),
                        ),
                        if (_start.isNotEmpty || _end.isNotEmpty)
                          pw.Text(
                            'Horario: $_start - $_end',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                      ],
                    ),
                    pw.Text(
                      dfTitle.format(date),
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Matrícula', 'Nombre', 'Estado'],
                data: List.generate(recs.length, (i) {
                  final r = recs[i].cast<String, dynamic>();
                  return [
                    '${i + 1}',
                    (r['studentId'] ?? '').toString(),
                    (r['name'] ?? '').toString(),
                    _statusText((r['status'] ?? '').toString()),
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
                columnWidths: {
                  0: const pw.FixedColumnWidth(24),
                  1: const pw.FixedColumnWidth(90),
                  3: const pw.FixedColumnWidth(70),
                },
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Resumen: Presentes $present • Retardos $late • Ausentes $absent • Total $total • Promedio $prom%',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
      ),
    );

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'asistencia_${groupId}_${DateFormat('yyyyMMdd').format(date)}.pdf',
    );
  }

  /// Exporta un rango de sesiones (una o varias materias/grupos) a PDF (resumen por fecha).
  static Future<void> exportPeriodPdf({
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> rows,
    String? titulo,
  }) async {
    if (rows.isEmpty) {
      throw Exception('No hay registros para exportar.');
    }

    // Orden por fecha ascendente
    rows.sort((a, b) {
      final da =
          DateTime.tryParse((a['date'] ?? a['id']).toString()) ??
          DateTime.now();
      final db =
          DateTime.tryParse((b['date'] ?? b['id']).toString()) ??
          DateTime.now();
      return da.compareTo(db);
    });

    // Totales globales
    int tp = 0, tl = 0, ta = 0, tt = 0;
    for (final r in rows) {
      tp += (r['present'] ?? r['presentCount'] ?? 0) as int;
      tl += (r['late'] ?? 0) as int;
      ta += (r['absent'] ?? 0) as int;
      tt += (r['total'] ?? 0) as int;
    }
    final prom = tt == 0 ? 0 : ((tp / tt) * 100).round();

    final dfTitle = DateFormat("d 'de' MMMM 'de' yyyy", 'es_MX');
    final dfRow = DateFormat('yyyy-MM-dd');

    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        build:
            (_) => [
              pw.Header(
                level: 0,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      titulo ?? 'Reporte de Asistencias',
                      style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                      ),
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
                headers: ['Fecha', 'Materia', 'Grupo', 'P', 'R', 'A', 'Total'],
                data:
                    rows.map((r) {
                      final dt =
                          DateTime.tryParse(
                            (r['date'] ?? r['id']).toString(),
                          ) ??
                          DateTime.now();
                      final subj = (r['subject'] ?? '').toString();
                      final gname = (r['groupName'] ?? '').toString();
                      final p = r['present'] ?? r['presentCount'] ?? 0;
                      final l = r['late'] ?? 0;
                      final a = r['absent'] ?? 0;
                      final tot = r['total'] ?? (p + l + a);
                      return [
                        dfRow.format(dt),
                        subj,
                        gname,
                        p.toString(),
                        l.toString(),
                        a.toString(),
                        tot.toString(),
                      ];
                    }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColors.grey300,
                ),
                cellAlignments: {
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
