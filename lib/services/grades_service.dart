// lib/services/grades_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// Si tu modelo GradeRecord está en otra ruta, ajusta el import:
import '../models/grade_models.dart';

class GradesService {
  GradesService._();
  static final GradesService instance = GradesService._();

  // ================== RUTAS ==================
  static String _uid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('No hay usuario autenticado.');
    }
    return uid;
  }

  static CollectionReference<Map<String, dynamic>> _activitiesCol(String groupId) {
    final uid = _uid();
    return FirebaseFirestore.instance
        .collection('teachers')
        .doc(uid)
        .collection('grades')
        .doc(groupId)
        .collection('activities');
  }

  // ================== API SIMPLE (la que ya usa tu UI) ==================
  /// Crea una actividad nueva con calificaciones.
  /// Regresa el `activityId` generado.
  Future<String> createActivity({
    required String groupId,
    required String groupName, // (no se usa, pero lo mantengo por compatibilidad)
    required String subject,   // (no se usa, pero lo mantengo por compatibilidad)
    required String title,
    required DateTime date,
    required List<GradeRecord> records,
  }) async {
    final id = _buildActivityId(date, title);
    await _activitiesCol(groupId).doc(id).set({
      'activity': title,
      'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
      'grades': _toGradesMap(records),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  /// Actualiza una actividad existente (nombre/fecha/calificaciones).
  /// Si al cambiar nombre/fecha cambia el ID, migra el documento.
  Future<String> updateActivity({
    required String groupId,
    required String activityId,
    required String title,
    required DateTime date,
    required List<GradeRecord> records,
  }) async {
    final newId = _buildActivityId(date, title);
    final col = _activitiesCol(groupId);

    if (newId == activityId) {
      // mismo id: solo actualizar
      await col.doc(activityId).set({
        'activity': title,
        'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
        'grades': _toGradesMap(records),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return activityId;
    } else {
      // migrar: copiar a nuevo id y borrar el viejo
      final old = await col.doc(activityId).get();
      final prev = old.data() ?? {};
      await col.doc(newId).set({
        ...prev,
        'activity': title,
        'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
        'grades': _toGradesMap(records),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await col.doc(activityId).delete();
      return newId;
    }
  }

  // ================== API UTILITARIA (por si la quieres usar) ==================
  static Future<String> saveActivity({
    required String groupId,
    required DateTime dateOnly,
    required String activityName,
    required Map<String, dynamic> gradesByStudentId,
    String? activityId,
  }) async {
    final id = activityId ?? _buildActivityId(dateOnly, activityName);
    final data = <String, dynamic>{
      'activity': activityName,
      'date': DateFormat('yyyy-MM-dd').format(_onlyDate(dateOnly)),
      'grades': gradesByStudentId,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _activitiesCol(groupId).doc(id).set(data, SetOptions(merge: true));
    return id;
  }

  static Future<String> updateActivityMeta({
    required String groupId,
    required String currentId,
    required DateTime newDateOnly,
    required String newName,
  }) async {
    final newId = _buildActivityId(newDateOnly, newName);
    final col = _activitiesCol(groupId);
    if (newId == currentId) {
      await col.doc(currentId).update({
        'activity': newName,
        'date': DateFormat('yyyy-MM-dd').format(_onlyDate(newDateOnly)),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return currentId;
    } else {
      final old = await col.doc(currentId).get();
      if (old.exists) {
        final data = old.data() ?? {};
        await col.doc(newId).set({
          ...data,
          'activity': newName,
          'date': DateFormat('yyyy-MM-dd').format(_onlyDate(newDateOnly)),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await col.doc(currentId).delete();
      }
      return newId;
    }
  }

  static Future<List<Map<String, dynamic>>> listActivitiesRaw({
    required String groupId,
  }) async {
    final snap = await _activitiesCol(groupId).get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  static Future<void> deleteActivity({
    required String groupId,
    required String activityId,
  }) async {
    await _activitiesCol(groupId).doc(activityId).delete();
  }

  // ================== Helpers ==================
  static Map<String, dynamic> _toGradesMap(List<GradeRecord> records) {
    // Guardamos solo la calificación (score). Si quieres incluir maxScore/comment, avísame y los agrego.
    final map = <String, dynamic>{};
    for (final r in records) {
      map[r.studentId] = r.score;
    }
    return map;
  }

  static DateTime _onlyDate(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _buildActivityId(DateTime date, String name) {
    final d = DateFormat('yyyy-MM-dd').format(_onlyDate(date));
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return '${d}__${slug.isEmpty ? 'actividad' : slug}';
  }
}
