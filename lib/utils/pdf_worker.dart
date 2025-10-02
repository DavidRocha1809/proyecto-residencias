// lib/utils/pdf_worker.dart
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PeriodArgs {
  PeriodArgs({
    required this.rows,
    required this.title,
    required this.fromLabel,
    required this.toLabel,
  });

  final List<Map<String, dynamic>> rows;
  final String title;
  final String fromLabel;
  final String toLabel;
}

class SessionArgs {
  SessionArgs({
    required this.rows,
    required this.title,
    required this.dateLabel,
  });

  final List<Map<String, dynamic>> rows;
  final String title;
  final String dateLabel;
}

Future<Uint8List> buildPeriodPdfBytes(PeriodArgs args) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(args.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Del: ${args.fromLabel}  Al: ${args.toLabel}'),
        pw.SizedBox(height: 12),
        pw.Table.fromTextArray(
          headers: const ['ID', 'Nombre', 'Asistencias', 'Retardos', 'Faltas'],
          data: args.rows.map((r) {
            return [
              (r['studentId'] ?? '').toString(),
              (r['name'] ?? '').toString(),
              (r['present'] ?? 0).toString(),
              (r['late'] ?? 0).toString(),
              (r['absent'] ?? 0).toString(),
            ];
          }).toList(),
        ),
      ],
    ),
  );
  return await doc.save();
}

Future<Uint8List> buildSessionPdfBytes(SessionArgs args) async {
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (ctx) => [
        pw.Text(args.title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Text('Fecha: ${args.dateLabel}'),
        pw.SizedBox(height: 12),
        pw.Table.fromTextArray(
          headers: const ['ID', 'Nombre', 'Estatus'],
          data: args.rows.map((r) {
            return [
              (r['studentId'] ?? '').toString(),
              (r['name'] ?? '').toString(),
              (r['status'] ?? '').toString(),
            ];
          }).toList(),
        ),
      ],
    ),
  );
  return await doc.save();
}
