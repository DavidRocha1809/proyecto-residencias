// lib/utils/helpers_csv.dart
import 'dart:convert';

import 'package:csv/csv.dart';

/// Estructura estándar para un alumno (mínima)
class StudentRow {
  final String studentId;
  final String name;

  StudentRow({required this.studentId, required this.name});

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'name': name,
      };
}

/// Estructura estándar para importación combinada Grupos + Alumnos
class GroupStudentRow {
  final String groupName; // p. ej. "3A", "4B"
  final String turno;     // "Matutino" / "Vespertino" / etc.
  final String dia;       // "Lunes" / "Martes" / ...
  final String subject;   // opcional
  final String studentId;
  final String name;

  GroupStudentRow({
    required this.groupName,
    required this.turno,
    required this.dia,
    required this.subject,
    required this.studentId,
    required this.name,
  });

  Map<String, dynamic> toMap() => {
        'groupName': groupName,
        'turno': turno,
        'dia': dia,
        'subject': subject,
        'studentId': studentId,
        'name': name,
      };
}

/// Limpia BOM y normaliza saltos de línea
String _normalizeText(String raw) {
  final text = raw.replaceAll('\uFEFF', '');
  return LineSplitter.split(text).join('\n');
}

/// Parsea un CSV genérico a listas de strings
List<List<dynamic>> _csv(String text) {
  return const CsvToListConverter(eol: '\n').convert(text);
}

/// Caso 1: CSV solo de alumnos (StudentsEditorPage) con columnas:
/// ID, NOMBRE
List<Map<String, dynamic>> parseStudentsCsvToList(String rawText) {
  final text = _normalizeText(rawText);
  final rows = _csv(text);
  final out = <Map<String, dynamic>>[];

  for (final r in rows) {
    if (r.isEmpty) continue;
    final sid = (r[0] ?? '').toString().trim();
    final name = (r.length > 1 ? r[1] : '').toString().trim();
    if (sid.isEmpty || name.isEmpty) continue;
    out.add(StudentRow(studentId: sid, name: name).toMap());
  }
  return out;
}

/// Caso 2: CSV para Dashboard con columnas:
/// GRUPO, TURNO, DIA, MATERIA, ID, NOMBRE
List<Map<String, dynamic>> parseGroupsAndStudentsCsvToList(String rawText) {
  final text = _normalizeText(rawText);
  final rows = _csv(text);
  final out = <Map<String, dynamic>>[];

  for (final r in rows) {
    if (r.isEmpty) continue;
    final groupName = (r.length > 0 ? r[0] : '').toString().trim();
    final turno     = (r.length > 1 ? r[1] : '').toString().trim();
    final dia       = (r.length > 2 ? r[2] : '').toString().trim();
    final subject   = (r.length > 3 ? r[3] : '').toString().trim();
    final sid       = (r.length > 4 ? r[4] : '').toString().trim();
    final name      = (r.length > 5 ? r[5] : '').toString().trim();

    if (groupName.isEmpty || turno.isEmpty || dia.isEmpty) continue;
    if (sid.isEmpty || name.isEmpty) continue;

    out.add(GroupStudentRow(
      groupName: groupName,
      turno: turno,
      dia: dia,
      subject: subject,
      studentId: sid,
      name: name,
    ).toMap());
  }
  return out;
}
