import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Guarda sesión (ya lo tenías)
  Future<void> saveSessionToFirestore({
    required String groupId,
    required String subject,
    required String groupName,
    required String start,
    required String end,
    required DateTime date,
    required List<Map<String, dynamic>> records,
  }) async {
    final id = _dateKey(date); // yyyy-MM-dd
    await _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .doc(id)
        .set({
          'teacherUid': _uid,
          'groupId': groupId,
          'subject': subject,
          'groupName': groupName,
          'start': start,
          'end': end,
          'date': id,
          'records': records,
          'present': records.where((r) => r['status'] == 'present').length,
          'late': records.where((r) => r['status'] == 'late').length,
          'absent': records.where((r) => r['status'] == 'absent').length,
          'total': records.length,
          'savedAt': DateTime.now().toIso8601String(),
        }, SetOptions(merge: true));
  }

  /// Lista sesiones (ya lo tenías)
  Future<List<Map<String, dynamic>>> listSessions({
    required String groupId,
    int limit = 100,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    CollectionReference col = _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions');

    Query q = col;
    // Como el ID del doc es yyyy-MM-dd, podemos filtrar por rango con where(FieldPath.documentId)
    if (dateFrom != null) {
      q = q.where(
        FieldPath.documentId,
        isGreaterThanOrEqualTo: _dateKey(dateFrom),
      );
    }
    if (dateTo != null) {
      q = q.where(FieldPath.documentId, isLessThanOrEqualTo: _dateKey(dateTo));
    }
    q = q.orderBy(FieldPath.documentId, descending: true).limit(limit);

    final snap = await q.get();
    return snap.docs
        .map((d) => {'docId': d.id, ...d.data() as Map<String, dynamic>})
        .toList();
  }

  /// NUEVO: trae una sesión específica (para generar PDF cloud→local)
  Future<Map<String, dynamic>?> getSessionByGroupAndDate({
    required String groupId,
    required DateTime date,
  }) async {
    final id = _dateKey(date);
    final doc =
        await _db
            .collection('teachers')
            .doc(_uid)
            .collection('attendance')
            .doc(groupId)
            .collection('sessions')
            .doc(id)
            .get();

    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>;
    return {'docId': doc.id, ...data};
  }

  /// (opcional) borrar por id de doc
  Future<void> deleteSessionById({
    required String groupId,
    required String docId,
  }) async {
    await _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .doc(docId)
        .delete();
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
