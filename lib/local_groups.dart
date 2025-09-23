import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'models.dart';

/// ==== Helpers de clave de grupo ====
String groupKeyFromParts(String groupName, String turno, String dia) {
  final s = '$groupName-$turno-$dia'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-');
  return s.replaceAll(RegExp(r'^-|-$'), '');
}

String groupKeyOf(GroupClass g) =>
    groupKeyFromParts(g.groupName, g.turno ?? 'NA', g.dia ?? 'NA');

/// ===================================================================
/// Almacén LOCAL (teléfono) para grupos y alumnos importados por CSV.
/// Guarda todo en el box Hive `local_groups`.
/// ===================================================================
class LocalGroups {
  static const _boxName = 'local_groups';

  static Future<Box> _ensureBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    return Hive.box(_boxName);
  }

  /// Guarda/actualiza metadatos del grupo (SOLO metadatos)
  static Future<void> upsertGroup({
    required String groupId,
    required String groupName,
    required String subject,
    required String turno,
    required String dia,
    String? start,
    String? end,
  }) async {
    final box = await _ensureBox();
    await box.put('group::$groupId', {
      'groupId': groupId,
      'groupName': groupName,
      'subject': subject,
      'turno': turno,
      'dia': dia,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
    });
  }

  /// Inserta/actualiza el listado de alumnos del grupo
  static Future<void> upsertStudentsBulk({
    required String groupId,
    required List<Map<String, dynamic>> students,
  }) async {
    final box = await _ensureBox();
    final norm =
        students
            .map(
              (s) => {
                'studentId':
                    (s['studentId'] ?? s['matricula'] ?? '').toString().trim(),
                'name': (s['name'] ?? '').toString(),
                if (s['n'] != null) 'n': s['n'],
              },
            )
            .where((m) => (m['studentId'] as String).isNotEmpty)
            .toList();
    await box.put('students::$groupId', norm);
  }

  /// Lista grupos guardados localmente (como `GroupClass` sin alumnos)
  static Future<List<GroupClass>> listGroups() async {
    final box = await _ensureBox();
    final keys =
        box.keys.where((k) => k.toString().startsWith('group::')).toList();

    TimeOfDay _parseTime(dynamic s) {
      if (s is String) {
        final p = s.split(':');
        if (p.length >= 2) {
          final h = int.tryParse(p[0]) ?? 0;
          final m = int.tryParse(p[1]) ?? 0;
          return TimeOfDay(hour: h, minute: m);
        }
      }
      return const TimeOfDay(hour: 0, minute: 0);
    }

    final List<GroupClass> res = [];
    for (final k in keys) {
      final m = (box.get(k) as Map).cast<String, dynamic>();
      res.add(
        GroupClass(
          groupName: m['groupName'] ?? '',
          subject: m['subject'] ?? '',
          start: _parseTime(m['start']),
          end: _parseTime(m['end']),
          students: const [], // se cargan al abrir la clase
          turno: m['turno'],
          dia: m['dia'],
        ),
      );
    }
    return res;
  }

  /// Regresa alumnos del grupo desde el almacenamiento local
  static Future<List<Student>> getStudents({required String groupId}) async {
    final box = await _ensureBox();
    final list = (box.get('students::$groupId') as List?) ?? const [];
    final docs = list.cast<Map>();

    // Ordena por 'n' si existe, si no por nombre
    docs.sort((a, b) {
      final an = a['n'];
      final bn = b['n'];
      if (an is int && bn is int) return an.compareTo(bn);
      final aname = (a['name'] ?? '').toString();
      final bname = (b['name'] ?? '').toString();
      return aname.compareTo(bname);
    });

    return docs
        .map(
          (m) => Student(
            id: (m['studentId'] ?? '').toString(),
            name: (m['name'] ?? '').toString(),
          ),
        )
        .toList();
  }
}

/// ===== Wrappers top-level por si llamas con alias `as LG` =====

Future<void> upsertGroup({
  required String groupId,
  required String groupName,
  required String subject,
  required String turno,
  required String dia,
  String? start,
  String? end,
}) => LocalGroups.upsertGroup(
  groupId: groupId,
  groupName: groupName,
  subject: subject,
  turno: turno,
  dia: dia,
  start: start,
  end: end,
);

Future<void> upsertStudentsBulk({
  required String groupId,
  required List<Map<String, dynamic>> students,
}) => LocalGroups.upsertStudentsBulk(groupId: groupId, students: students);

Future<List<GroupClass>> listGroups() => LocalGroups.listGroups();

Future<List<Student>> getStudents(String groupId) =>
    LocalGroups.getStudents(groupId: groupId);
