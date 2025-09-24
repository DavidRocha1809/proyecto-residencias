import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models.dart';

/// Llave única de grupo a partir de (grupo + turno + día)
String groupKeyFromParts(String groupName, String? turno, String? dia) {
  final t = (turno ?? '').trim();
  final d = (dia ?? '').trim();
  return '$groupName|$t|$d';
}

/// Llave única de grupo a partir de un GroupClass
String groupKeyOf(GroupClass g) =>
    groupKeyFromParts(g.groupName, g.turno, g.dia);

class LocalGroups {
  // Nombres de boxes
  static const String _boxGroups = 'groups'; // grupos
  // alumnos se guardan en boxes por grupo: 'students::<groupId>'

  /// Asegura que el box de grupos esté abierto
  static Future<Box> _ensureGroupsBox() async {
    if (!Hive.isBoxOpen(_boxGroups)) {
      await Hive.openBox(_boxGroups);
    }
    return Hive.box(_boxGroups);
  }

  /// Asegura que el box de alumnos para un groupId esté abierto
  static Future<Box> _ensureStudentsBox(String groupId) async {
    final name = 'students::$groupId';
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox(name);
    }
    return Hive.box(name);
  }

  /// Inserta/actualiza un grupo
  static Future<void> upsertGroup({
    required String groupId,
    required String groupName,
    required String subject,
    required String turno,
    required String dia,
    String? start,
    String? end,
  }) async {
    final box = await _ensureGroupsBox();
    await box.put(groupId, {
      'groupId': groupId,
      'groupName': groupName,
      'subject': subject,
      'turno': turno,
      'dia': dia,
      'start': start, // HH:mm
      'end': end, // HH:mm
    });
  }

  /// Retorna todos los grupos como `GroupClass`
  static Future<List<GroupClass>> listGroups() async {
    final box = await _ensureGroupsBox();
    final List<GroupClass> out = [];
    for (final key in box.keys) {
      final m = box.get(key);
      if (m is Map) {
        final data = m.cast<String, dynamic>();
        // Parseo de horario HH:mm -> TimeOfDay
        TimeOfDay _parseTime(String? s) {
          if (s == null || s.isEmpty)
            return const TimeOfDay(hour: 0, minute: 0);
          final p = s.split(':');
          final h = int.tryParse(p[0]) ?? 0;
          final min = int.tryParse(p[1]) ?? 0;
          return TimeOfDay(hour: h, minute: min);
        }

        out.add(
          GroupClass(
            groupName: (data['groupName'] ?? '').toString(),
            subject: (data['subject'] ?? '').toString(),
            turno: (data['turno'] ?? '').toString(),
            dia: (data['dia'] ?? '').toString(),
            start: _parseTime(data['start']?.toString()),
            end: _parseTime(data['end']?.toString()),
            // Importante: aquí NO cargamos alumnos; se cargan aparte por groupId
            students: const <Student>[],
          ),
        );
      }
    }
    return out;
  }

  /// Guarda (inserta/actualiza) alumnos en bloque para un grupo.
  /// Espera objetos tipo: { 'studentId': 'xxx', 'name': '...' }
  static Future<void> upsertStudentsBulk({
    required String groupId,
    required List<Map<String, dynamic>> students,
  }) async {
    final box = await _ensureStudentsBox(groupId);

    // Guardamos por clave studentId para deduplicar
    for (final s in students) {
      final sid = (s['studentId'] ?? '').toString().trim();
      if (sid.isEmpty) continue;
      final name = (s['name'] ?? '').toString().trim();
      await box.put(sid, {'id': sid, 'name': name});
    }
  }

  /// Lista alumnos de un grupo como `List<Student>` (para AttendancePage)
  static Future<List<Student>> listStudents({required String groupId}) async {
    final box = await _ensureStudentsBox(groupId);
    final List<Student> out = [];
    for (final key in box.keys) {
      final m = box.get(key);
      if (m is Map) {
        final data = m.cast<String, dynamic>();
        out.add(
          Student(
            id: (data['id'] ?? '').toString(),
            name: (data['name'] ?? '').toString(),
            status: AttendanceStatus.none, // la pantalla lo ajusta a 'present'
          ),
        );
      }
    }
    // Orden por nombre (opcional)
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}
