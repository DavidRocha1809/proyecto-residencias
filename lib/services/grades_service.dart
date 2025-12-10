import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/grade_models.dart';

class GradesService {
  GradesService._();
  static final GradesService instance = GradesService._();

  // ================== HELPERS ==================
  static String _uid() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('No hay usuario autenticado.');
    return uid;
  }

  /// 🔹 Limpia el ID del grupo (reemplaza | por _)
  static String _safeGroupId(String groupId) =>
      groupId.replaceAll('|', '_').replaceAll(' ', '_');

  static CollectionReference<Map<String, dynamic>> _activitiesCol(
      String groupId) {
    final uid = _uid();
    final cleanGroupId = _safeGroupId(groupId);
    return FirebaseFirestore.instance
        .collection('teachers')
        .doc(uid)
        .collection('grades')
        .doc(cleanGroupId)
        .collection('activities');
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

  /// Nombre de la caja Hive utilizada para almacenar actividades de calificaciones offline.
  static const String _offlineBoxName = 'offline_grades';

  /// 🔄 Sincroniza actividades de calificaciones guardadas en Hive cuando hay conexión.
  Future<void> syncPendingData() async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) return;

    final box = await Hive.openBox(_offlineBoxName);
    final keys = box.keys.toList();
    for (final key in keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final data = Map<String, dynamic>.from(raw);
        final String groupId = data['groupId'] as String;
        final String activityId = data['activityId'] as String;
        final String? oldActivityId = data['oldActivityId'] as String?;
        final String title = data['title'] as String;
        final String dateStr = data['date'] as String;
        final Map<String, dynamic> grades =
        Map<String, dynamic>.from(data['grades'] as Map);

        final DateTime date = DateTime.parse(dateStr);
        final col = _activitiesCol(groupId);
        await col.doc(activityId).set({
          'activity': title,
          'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
          'grades': grades,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        if (oldActivityId != null && oldActivityId != activityId) {
          await col.doc(oldActivityId).delete();
        }
        await box.delete(key);
      }
    }
  }

  // ================== CRUD PRINCIPAL ==================
  Future<String> createActivity({
    required String groupId,
    required String title,
    required DateTime date,
    required List<GradeRecord> records,
  }) async {
    final id = _buildActivityId(date, title);
    final gradesMap = _toGradesMap(records);
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      final box = await Hive.openBox(_offlineBoxName);
      await box.put(id, {
        'groupId': groupId,
        'activityId': id,
        'oldActivityId': null,
        'title': title,
        'date': _onlyDate(date).toIso8601String(),
        'grades': gradesMap,
      });
      return id;
    }
    await _activitiesCol(groupId).doc(id).set({
      'activity': title,
      'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
      'grades': gradesMap,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<String> updateActivity({
    required String groupId,
    required String activityId,
    required String title,
    required DateTime date,
    required List<GradeRecord> records,
  }) async {
    final newId = _buildActivityId(date, title);
    final gradesMap = _toGradesMap(records);
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      final box = await Hive.openBox(_offlineBoxName);
      await box.put(newId, {
        'groupId': groupId,
        'activityId': newId,
        'oldActivityId': newId == activityId ? null : activityId,
        'title': title,
        'date': _onlyDate(date).toIso8601String(),
        'grades': gradesMap,
      });
      if (newId != activityId) {
        await box.delete(activityId);
      }
      return newId;
    }

    final col = _activitiesCol(groupId);
    if (newId == activityId) {
      await col.doc(activityId).set({
        'activity': title,
        'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
        'grades': gradesMap,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return activityId;
    } else {
      final old = await col.doc(activityId).get();
      final prev = old.data() ?? {};
      await col.doc(newId).set({
        ...prev,
        'activity': title,
        'date': DateFormat('yyyy-MM-dd').format(_onlyDate(date)),
        'grades': gradesMap,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await col.doc(activityId).delete();
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
    final map = <String, dynamic>{};
    for (final r in records) {
      map[r.studentId] = r.score;
    }
    return map;
  }
}
