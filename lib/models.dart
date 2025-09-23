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
}

class GroupClass {
  final String groupName;
  final String subject;
  final TimeOfDay start;
  final TimeOfDay end;
  final List<Student> students;

  // Extras
  final String? turno; // "Matutino" | "Vespertino"
  final String? dia; // "Lunes" | "Martes" | ...

  GroupClass({
    required this.groupName,
    required this.subject,
    required this.start,
    required this.end,
    required this.students,
    this.turno,
    this.dia,
  });
}

String fmtTime(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, "0")}:${t.minute.toString().padLeft(2, "0")}';
