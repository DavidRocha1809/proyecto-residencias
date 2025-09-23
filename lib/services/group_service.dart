import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models.dart';

class GroupService {
  GroupService._();
  static final instance = GroupService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get _uid {
    final u = _auth.currentUser?.uid;
    if (u == null) throw StateError('No hay sesión iniciada');
    return u;
  }

  String slug(String groupName, String turno, String dia) {
    final s = '$groupName-$turno-$dia'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-');
    return s.replaceAll(RegExp(r'^-|-$'), '');
  }

  Future<void> upsertGroup({
    required String groupName,
    required String subject,
    required String turno,
    required String dia,
    String? start,
    String? end,
  }) async {
    final groupId = slug(groupName, turno, dia);
    final ref = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId);

    await ref.set({
      'groupId': groupId,
      'groupName': groupName,
      'subject': subject,
      'turno': turno,
      'dia': dia,
      if (start != null) 'start': start,
      if (end != null) 'end': end,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // lib/services/group_service.dart

  Future<void> upsertStudentsBulk({
    required String groupId,
    required List<Map<String, dynamic>>
    students, // <- dynamic para permitir 'n' int
  }) async {
    final batch = _db.batch();
    final base = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId)
        .collection('students');

    for (final s in students) {
      final sid = (s['studentId'] ?? s['matricula'] ?? '').toString().trim();
      if (sid.isEmpty) continue;

      batch.set(base.doc(sid), {
        // guardamos ambos nombres por compatibilidad
        'studentId': sid,
        'matricula': sid,
        'name': (s['name'] ?? '').toString(),
        if (s['n'] != null) 'n': s['n'], // contador opcional
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<List<Map<String, dynamic>>> getGroupsOnce() async {
    final snap =
        await _db
            .collection('teachers')
            .doc(_uid)
            .collection('groups')
            .orderBy('groupName')
            .get();
    return snap.docs.map((d) => d.data()).toList();
  }

  Future<List<Student>> getStudentsOnce({required String groupId}) async {
    final col = _db
        .collection('teachers')
        .doc(_uid)
        .collection('groups')
        .doc(groupId)
        .collection('students');

    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await col.orderBy('n').get();
    } catch (_) {
      snap = await col.orderBy('name').get();
    }

    return snap.docs.map((d) {
      final data = d.data();
      final id = (data['matricula'] ?? data['studentId'] ?? d.id).toString();
      final name = (data['name'] ?? '').toString();
      return Student(id: id, name: name); // <-- ahora sí existe Student
    }).toList();
  }
}
