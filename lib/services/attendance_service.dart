import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final u = _auth.currentUser?.uid;
    if (u == null) throw StateError('No hay sesión iniciada');
    return u;
  }

  /// Crea/actualiza una sesión de asistencia (doc: sessions/{yyyy-MM-dd})
  Future<void> saveAttendance({
    required String groupId,
    required String yyyymmdd,
    required List<Map<String, dynamic>> students,
    Map<String, dynamic>? sessionMeta,
  }) async {
    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId)
        .collection('sessions')
        .doc(yyyymmdd);

    final present = students.where((m) => m['status'] == 'present').length;
    final late = students.where((m) => m['status'] == 'late').length;
    final absent = students.where((m) => m['status'] == 'absent').length;

    await ref.set({
      'id': yyyymmdd,
      'date': yyyymmdd,
      'students': students,
      'present': present,
      'late': late,
      'absent': absent,
      'updatedAt': FieldValue.serverTimestamp(),
      if (sessionMeta != null) ...sessionMeta,
    }, SetOptions(merge: true));
  }

  /// Lee una sesión específica
  Future<Map<String, dynamic>?> fetchSession({
    required String groupId,
    required String yyyymmdd,
  }) async {
    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId)
        .collection('sessions')
        .doc(yyyymmdd);

    final snap = await ref.get();
    if (!snap.exists) return null;
    return snap.data();
  }

  /// Lista sesiones del grupo (con filtros por fecha opcionales)
  Future<List<Map<String, dynamic>>> listSessions({
    required String groupId,
    int limit = 200,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId)
        .collection('sessions')
        .orderBy('date', descending: true);

    if (dateFrom != null) {
      final from = DateFormat('yyyy-MM-dd').format(dateFrom);
      q = q.where('date', isGreaterThanOrEqualTo: from);
    }
    if (dateTo != null) {
      final to = DateFormat('yyyy-MM-dd').format(dateTo);
      q = q.where('date', isLessThanOrEqualTo: to);
    }

    q = q.limit(limit);
    final snap = await q.get();
    return snap.docs.map((d) => d.data()).toList();
  }

  /// 🔴 Eliminar una sesión (para tu botón "Eliminar")
  Future<void> deleteAttendance({
    required String groupId,
    required String yyyymmdd,
  }) async {
    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId)
        .collection('sessions')
        .doc(yyyymmdd);
    await ref.delete();
  }
}