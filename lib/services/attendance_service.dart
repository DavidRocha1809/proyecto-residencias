import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class AttendanceService {
  AttendanceService._();
  static final instance = AttendanceService._();

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  /// 🔹 Guarda la sesión (usa Hive si no hay red)
  Future<void> saveSessionToFirestore({
    required String groupId,
    required String subject,
    required String groupName,
    required String start,
    required String end,
    required DateTime date,
    required List<Map<String, dynamic>> records,
  }) async {
    final uid = _auth.currentUser!.uid;
    final docId =
        '${groupName}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    final data = {
      'groupId': groupId,
      'subject': subject,
      'groupName': groupName,
      'start': start,
      'end': end,
      'date': date.toIso8601String(),
      'records': records,
      'timestamp': FieldValue.serverTimestamp(),
    };

    final conn = await Connectivity().checkConnectivity();

    if (conn == ConnectivityResult.none) {
      // 📦 Guardar localmente si no hay red
      final box = await Hive.openBox('offline_attendance');
      await box.put(docId, data);
      print('📦 Guardado localmente ($docId) sin conexión');
      return;
    }

    // ☁️ Guardar en Firestore
    await _firestore
        .collection('teachers')
        .doc(uid)
        .collection('attendance')
        .doc(docId)
        .set(data, SetOptions(merge: true));

    print('☁️ Enviado correctamente a Firestore ($docId)');
  }

  /// 🔹 Sube pendientes de Hive cuando vuelva internet
  Future<void> syncPendingData() async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) return;

    final box = await Hive.openBox('offline_attendance');
    final keys = box.keys.toList();

    for (final key in keys) {
      final data = box.get(key);
      if (data != null) {
        final uid = _auth.currentUser!.uid;
        await _firestore
            .collection('teachers')
            .doc(uid)
            .collection('attendance')
            .doc(key)
            .set(Map<String, dynamic>.from(data), SetOptions(merge: true));
        print('☁️ Sincronizado $key con Firestore');
        await box.delete(key);
      }
    }
  }

  /// 🔹 Actualiza el campo de registros en una sesión.
  /// Si no hay conexión, actualiza el registro guardado en Hive o lo crea si no existe.
  Future<void> updateSessionRecords({
    required String docId,
    required List<Map<String, dynamic>> records,
  }) async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      final box = await Hive.openBox('offline_attendance');
      final existing = box.get(docId);
      if (existing != null && existing is Map) {
        final data = Map<String, dynamic>.from(existing);
        data['records'] = records;
        data['timestamp'] = DateTime.now().toIso8601String();
        await box.put(docId, data);
      } else {
        await box.put(docId, {
          'records': records,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
      return;
    }

    final uid = _auth.currentUser!.uid;
    await _firestore
        .collection('teachers')
        .doc(uid)
        .collection('attendance')
        .doc(docId)
        .update({'records': records});
  }

  // ========================================================
  // 🔹 Listar sesiones guardadas (para reportes)
  // ========================================================
  Future<List<Map<String, dynamic>>> listSessions({
    required String groupId,
    DateTime? dateFrom,
    DateTime? dateTo,
    int limit = 1000,
  }) async {
    final uid = _auth.currentUser!.uid;
    final col = _firestore
        .collection('teachers')
        .doc(uid)
        .collection('attendance');

    Query query = col.where('groupId', isEqualTo: groupId);

    if (dateFrom != null) {
      query = query.where(
        'date',
        isGreaterThanOrEqualTo: dateFrom.toIso8601String(),
      );
    }
    if (dateTo != null) {
      query = query.where(
        'date',
        isLessThanOrEqualTo: dateTo.toIso8601String(),
      );
    }

    final snap = await query.limit(limit).get();

    // ✅ Conversión segura con tipado explícito
    final List<Map<String, dynamic>> sessions = snap.docs.map((doc) {
      final Map<String, dynamic> data =
          doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};

      // Agregamos el ID del documento
      data['id'] = doc.id;

      return data;
    }).toList();

    return sessions;
  }
}
