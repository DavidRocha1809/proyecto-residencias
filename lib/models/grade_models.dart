// lib/models/grade_models.dart

/// Un registro de calificación para un alumno en una actividad.
class GradeRecord {
  final String studentId;
  final String studentName;
  final double score;     // calificación obtenida
  final double? maxScore; // opcional, para porcentaje o base
  final String? comment;  // observaciones

  GradeRecord({
    required this.studentId,
    required this.studentName,
    required this.score,
    this.maxScore,
    this.comment,
  });

  Map<String, dynamic> toMap() => {
        'studentId': studentId,
        'studentName': studentName,
        'score': score,
        'maxScore': maxScore,
        'comment': comment,
      };

  factory GradeRecord.fromMap(Map<String, dynamic> map) => GradeRecord(
        studentId: map['studentId'] as String,
        studentName: map['studentName'] as String,
        score: (map['score'] as num).toDouble(),
        maxScore: map['maxScore'] == null ? null : (map['maxScore'] as num).toDouble(),
        comment: map['comment'] as String?,
      );
}

/// Actividad de calificaciones (similar a "sesión" en asistencias).
class GradeActivity {
  final String id; // activityId (doc id en Firestore)
  final String groupId;
  final String groupName;
  final String subject;
  final String title; // nombre de la actividad (p.ej. "Proyecto 1")
  final DateTime date;
  final List<GradeRecord> records;

  GradeActivity({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.subject,
    required this.title,
    required this.date,
    required this.records,
  });

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'groupName': groupName,
        'subject': subject,
        'title': title,
        'date': date.toIso8601String(),
        'records': records.map((e) => e.toMap()).toList(),
      };

  factory GradeActivity.fromDoc(String id, Map<String, dynamic> map) {
    final recs = (map['records'] as List<dynamic>? ?? [])
        .map((e) => GradeRecord.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    return GradeActivity(
      id: id,
      groupId: map['groupId'] as String,
      groupName: map['groupName'] as String,
      subject: map['subject'] as String,
      title: map['title'] as String,
      date: DateTime.parse(map['date'] as String),
      records: recs,
    );
  }
}
