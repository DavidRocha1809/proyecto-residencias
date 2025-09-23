import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// /teachers/{teacherId}/attendance/{groupId}/sessions/{yyyy-MM-dd}
class AttendanceService {
  AttendanceService._();
  static final AttendanceService instance = AttendanceService._();

  final _db = FirebaseFirestore.instance;

  String _teacherId([String? teacherId]) {
    final uid = teacherId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw Exception(
        'Sin autenticación. Inicia sesión (anónima o proveedor) para acceder a /teachers/{uid}/…',
      );
    }
    return uid;
  }

  CollectionReference<Map<String, dynamic>> _sessionsColl({
    required String groupId,
    String? teacherId,
  }) {
    final tid = _teacherId(teacherId);
    return _db
        .collection('teachers')
        .doc(tid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions');
  }

  Future<void> saveAttendance({
    required String groupId,
    required String yyyymmdd,
    required List<Map<String, dynamic>> students,
    Map<String, dynamic>? sessionMeta,
    String? teacherId,
  }) async {
    final doc = _sessionsColl(groupId: groupId, teacherId: teacherId).doc(yyyymmdd);

    int p = 0, r = 0, a = 0;
    for (final s in students) {
      final st = (s['status'] ?? 'none').toString();
      if (st == 'present') p++;
      if (st == 'late') r++;
      if (st == 'absent') a++;
    }
    final total = students.length;

    await doc.set({
      'date': yyyymmdd,
      'updatedAt': FieldValue.serverTimestamp(),
      'students': students,
      'present': p,
      'late': r,
      'absent': a,
      'total': total,
      if (sessionMeta != null) ...sessionMeta,
    }, SetOptions(merge: true));
  }

  Future<List<Map<String, dynamic>>> listSessions({
    required String groupId,
    int limit = 50,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? teacherId,
  }) async {
    final coll = _sessionsColl(groupId: groupId, teacherId: teacherId);
    Query<Map<String, dynamic>> q = coll.orderBy('date', descending: true);

    if (dateFrom != null && dateTo != null) {
      final d = _fmt(dateFrom);
      q = coll.where('date', isEqualTo: d);
    } else if (dateFrom != null) {
      final d = _fmt(dateFrom);
      q = coll.where('date', isGreaterThanOrEqualTo: d);
    }
    if (limit > 0) q = q.limit(limit);

    final snap = await q.get();
    return snap.docs.map((d) => d.data()..['id'] = d.id).toList();
  }

  Future<void> deleteAttendance({
    required String groupId,
    required String yyyymmdd,
    String? teacherId,
  }) async {
    final doc = _sessionsColl(groupId: groupId, teacherId: teacherId).doc(yyyymmdd);
    await doc.delete();
  }

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
