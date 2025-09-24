import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  final _auth = FirebaseAuth.instance;
  final _fs = FirebaseFirestore.instance;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) {
      throw Exception('No hay usuario autenticado.');
    }
    return u.uid;
  }

  /// Colección: teachers/{uid}/attendance/{groupId}/sessions
  CollectionReference<Map<String, dynamic>> _sessionsCol(String groupId) {
    return _fs
        .collection('teachers')
        .doc(_uid)
        .collection('attendance')
        .doc(groupId)
        .collection('sessions');
  }

  /// ID por día (igual a tu consola): yyyy-MM-dd
  String _docIdFromDate(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  /// Crear/actualizar sesión del día
  Future<void> saveSessionToFirestore({
    required String groupId,
    required String subject,
    required String groupName,
    required String start, // "HH:mm"
    required String end,   // "HH:mm"
    required DateTime date,
    required List<Map<String, dynamic>> records, // [{studentId,name,status}]
  }) async {
    final col = _sessionsCol(groupId);
    final docId = _docIdFromDate(date);

    int present = 0, late = 0, absent = 0;
    for (final r in records) {
      final s = (r['status'] ?? '').toString();
      if (s == 'present') present++;
      else if (s == 'late') late++;
      else if (s == 'absent') absent++;
    }
    final total = records.length;

    final payload = {
      'teacherUid': _uid,
      'groupId': groupId,
      'subject': subject,
      'groupName': groupName,
      'start': start,
      'end': end,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'dateTs': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'present': present,
      'late': late,
      'absent': absent,
      'total': total,
      'records': records,
      'savedAt': FieldValue.serverTimestamp(),
    };

    await col.doc(docId).set(payload, SetOptions(merge: true));
  }

  /// Lista sesiones (query por un solo campo: dateTs → sin índice compuesto)
  Future<List<Map<String, dynamic>>> listSessions({
    required String groupId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 100,
  }) async {
    Query<Map<String, dynamic>> q =
        _sessionsCol(groupId).orderBy('dateTs', descending: true);

    if (dateFrom != null) {
      q = q.where(
        'dateTs',
        isGreaterThanOrEqualTo: Timestamp.fromDate(
          DateTime(dateFrom.year, dateFrom.month, dateFrom.day),
        ),
      );
    }
    if (dateTo != null) {
      final toEnd =
          DateTime(dateTo.year, dateTo.month, dateTo.day, 23, 59, 59);
      q = q.where('dateTs', isLessThanOrEqualTo: Timestamp.fromDate(toEnd));
    }

    q = q.limit(limit);
    final snap = await q.get();
    // Estandarizamos la clave del id del doc como 'docId'
    return snap.docs.map((d) => {'docId': d.id, ...d.data()}).toList();
  }

  /// Leer una sesión específica
  Future<Map<String, dynamic>?> getSession({
    required String groupId,
    required DateTime date,
  }) async {
    final d = await _sessionsCol(groupId).doc(_docIdFromDate(date)).get();
    if (!d.exists) return null;
    return {'docId': d.id, ...?d.data()};
  }

  /// Eliminar por fecha
  Future<void> deleteSession({
    required String groupId,
    required DateTime date,
  }) async {
    await _sessionsCol(groupId).doc(_docIdFromDate(date)).delete();
  }

  /// ✅ NUEVO: Eliminar por docId (lo que pedía tu pantalla)
  Future<void> deleteSessionById({
    required String groupId,
    required String docId,
  }) async {
    await _sessionsCol(groupId).doc(docId).delete();
  }
}
