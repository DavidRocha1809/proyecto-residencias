import 'package:flutter/material.dart';

enum AttendanceStatus { none, present, late, absent }

class Student {
  final String id;
  final String name;
  AttendanceStatus status;

  Student({
    required this.id,
    required this.name,
    this.status = AttendanceStatus.none,
  });

  // 🔹 Conversión a JSON (para subir a Firestore)
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status.name,
      };

  // 🔹 Crear desde JSON (para leer de Firestore)
  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: json['id'] ?? '',
        name: json['name'] ?? '',
        status: AttendanceStatus.values.firstWhere(
          (e) => e.name == (json['status'] ?? 'none'),
          orElse: () => AttendanceStatus.none,
        ),
      );
}

class GroupClass {
  /// ID único del grupo (por ejemplo: "3E" o "5A")
  final String id;

  final String groupName;

  /// Nombre de la materia (por ejemplo: "Matemáticas")
  final String subject;

  /// Hora de inicio
  final TimeOfDay start;

  /// Hora de fin
  final TimeOfDay end;

  /// Lista de alumnos
  final List<Student> students;

  /// Turno (opcional): "Matutino" | "Vespertino"
  final String? turno;

  /// Día (opcional): "Lunes" | "Martes" | ...
  final String? dia;

  GroupClass({
    required this.id,
    required this.groupName,
    required this.subject,
    required this.start,
    required this.end,
    required this.students,
    this.turno,
    this.dia,
  });

  // 🔹 Convertir a JSON (útil para guardar en Firestore)
  Map<String, dynamic> toJson() => {
        'id': id,
        'groupName': groupName,
        'subject': subject,
        'start': fmtTime(start),
        'end': fmtTime(end),
        'turno': turno,
        'dia': dia,
        'students': students.map((s) => s.toJson()).toList(),
      };

  // 🔹 Crear desde JSON (útil para leer de Firestore)
  factory GroupClass.fromJson(Map<String, dynamic> json) => GroupClass(
        id: json['id'] ?? '',
        groupName: json['groupName'] ?? '',
        subject: json['subject'] ?? '',
        start: _parseTime(json['start']),
        end: _parseTime(json['end']),
        turno: json['turno'],
        dia: json['dia'],
        students: (json['students'] as List<dynamic>? ?? [])
            .map((s) => Student.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
      );
}

/// 🔹 Formatea un TimeOfDay a HH:mm
String fmtTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';

/// 🔹 Convierte un string HH:mm en TimeOfDay
TimeOfDay _parseTime(String? t) {
  if (t == null || !t.contains(':')) return const TimeOfDay(hour: 0, minute: 0);
  final parts = t.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: int.tryParse(parts[1]) ?? 0,
  );
}
