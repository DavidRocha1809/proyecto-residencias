import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  /// Guarda (crea/sobrescribe) una sesión (ya lo tenías).
  Future<void> saveSessionToFirestore({
    required String groupId,
    required String subject,
    required String groupName,
    required String start,
    required String end,
    required DateTime date,
    required List<Map<String, dynamic>> records,
  }) async {
    final docId = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .doc(docId);

    await ref.set({
      'teacherUid': _uid,
      'groupId': groupId,
      'subject': subject,
      'groupName': groupName,
      'start': start,
      'end': end,
      'date': docId,
      'records': records,
      'present': records.where((r) => r['status'] == 'present').length,
      'late': records.where((r) => r['status'] == 'late').length,
      'absent': records.where((r) => r['status'] == 'absent').length,
      'total': records.length,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Lista sesiones para un grupo entre fechas (lo usas en historial).
  Future<List<Map<String, dynamic>>> listSessions({
    required String groupId,
    int limit = 500,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    var q = _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .orderBy('date', descending: true);

    if (dateFrom != null) {
      final f = '${dateFrom.year.toString().padLeft(4, '0')}-'
          '${dateFrom.month.toString().padLeft(2, '0')}-'
          '${dateFrom.day.toString().padLeft(2, '0')}';
      q = q.where('date', isGreaterThanOrEqualTo: f);
    }
    if (dateTo != null) {
      final t = '${dateTo.year.toString().padLeft(4, '0')}-'
          '${dateTo.month.toString().padLeft(2, '0')}-'
          '${dateTo.day.toString().padLeft(2, '0')}';
      q = q.where('date', isLessThanOrEqualTo: t);
    }

    final snap = await q.limit(limit).get();
    return snap.docs
        .map((d) => {'docId': d.id, ...d.data()})
        .cast<Map<String, dynamic>>()
        .toList();
  }

  /// 🔎 Trae una sesión exacta por grupo+fecha (para editar o exportar)
  Future<Map<String, dynamic>?> getSessionByGroupAndDate({
    required String groupId,
    required DateTime date,
  }) async {
    final docId = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .doc(docId);

    final d = await ref.get();
    if (!d.exists) return null;
    return {'docId': d.id, ...d.data()!};
  }

  /// 📝 Actualiza SOLO los records (y contadores) de una sesión existente
  Future<void> updateSessionById({
    required String groupId,
    required String docId, // normalmente yyyy-MM-dd
    required List<Map<String, dynamic>> records,
  }) async {
    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .doc(docId);

    await ref.update({
      'records': records,
      'present': records.where((r) => r['status'] == 'present').length,
      'late': records.where((r) => r['status'] == 'late').length,
      'absent': records.where((r) => r['status'] == 'absent').length,
      'total': records.length,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// 🗑️ Eliminar (ya lo usabas desde historial)
  Future<void> deleteSessionById({
    required String groupId,
    required String docId,
  }) async {
    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions')
        .doc(docId);
    await ref.delete();
  }
}
