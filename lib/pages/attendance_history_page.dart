// lib/pages/attendance_history_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'edit_attendance_page.dart';
import '../utils/attendance_pdf.dart';
import 'attendance_student_selection_page.dart';
import '../models.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final String groupName; // ✅ ID real del grupo (por ejemplo: 3E)
  final String? displayName; // ✅ Nombre visual (por ejemplo: Humanidades 2)

  const AttendanceHistoryPage({
    super.key,
    required this.groupName,
    this.displayName,
  });

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  @override
  void initState() {
    super.initState();
    _setFirestoreNetworkState();
  }

  /// Activa o desactiva la red de Firestore según la conectividad.
  Future<void> _setFirestoreNetworkState() async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) {
      await FirebaseFirestore.instance.disableNetwork();
    } else {
      await FirebaseFirestore.instance.enableNetwork();
    }
  }

  // ============================================================
  // 🔹 Obtiene solo las sesiones del grupo seleccionado (EN VIVO)
  //    Filtradas por nombre de grupo y rango de fechas
  // ============================================================
  Stream<List<Map<String, dynamic>>> _getAllSessions() {
    final firestore = FirebaseFirestore.instance;
    final attendanceRef =
    firestore.collection('teachers').doc(uid).collection('attendance');

    return attendanceRef.snapshots().map((snap) {
      var allSessions = snap.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // 🔹 Filtrar por grupo (nombre o ID)
      allSessions = allSessions
          .where((s) =>
          (s['groupName'] ?? s['groupId'] ?? '')
              .toString()
              .toLowerCase()
              .contains(widget.groupName.toLowerCase()))
          .toList();

      // 🔹 Filtrar por rango de fechas
      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);

      final filtered = allSessions.where((s) {
        final d = _safeParseDate(s['date']);
        return !d.isBefore(from) && !d.isAfter(to);
      }).toList();

      // 🔹 Ordenar por fecha (más reciente primero)
      filtered.sort((a, b) {
        final aDate = _safeParseDate(a['date']);
        final bDate = _safeParseDate(b['date']);
        return bDate.compareTo(aDate);
      });

      print('📡 Actualización detectada en historial (${filtered.length} registros)');
      return filtered;
    });
  }

  // ============================================================
  // 🔹 Funciones auxiliares
  // ============================================================
  DateTime _safeParseDate(dynamic value) {
    if (value == null) return DateTime(0);
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {
        final regex = RegExp(r'(\d{1,2})\s+de\s+(\w+)\s+de\s+(\d{4})');
        final match = regex.firstMatch(value);
        if (match != null) {
          final day = int.tryParse(match.group(1)!);
          final month = _monthFromSpanish(match.group(2)!);
          final year = int.tryParse(match.group(3)!);
          if (day != null && month != null && year != null) {
            return DateTime(year, month, day);
          }
        }
      }
    }
    return DateTime(0);
  }

  int? _monthFromSpanish(String name) {
    const meses = {
      'enero': 1,
      'febrero': 2,
      'marzo': 3,
      'abril': 4,
      'mayo': 5,
      'junio': 6,
      'julio': 7,
      'agosto': 8,
      'septiembre': 9,
      'setiembre': 9,
      'octubre': 10,
      'noviembre': 11,
      'diciembre': 12,
    };
    return meses[name.toLowerCase()];
  }

  Future<void> _pickFrom() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      locale: const Locale('es', 'MX'),
    );
    if (r != null) setState(() => _from = r);
  }

  Future<void> _pickTo() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      locale: const Locale('es', 'MX'),
    );
    if (r != null) setState(() => _to = r);
  }

  // ============================================================
  // 🔹 Eliminar registro
  // ============================================================
  Future<void> _deleteSession(
      String docId, String groupName, String dateText) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: Text(
          '¿Seguro que deseas eliminar la lista del grupo "$groupName" del $dateText?\n\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('teachers')
          .doc(uid)
          .collection('attendance')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Registro eliminado correctamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar: $e')),
        );
      }
    }
  }

  // ============================================================
  // 🔹 UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text('Historial de ${widget.groupName}'),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // 🔸 Filtros de fecha
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickFrom,
                        icon: const Icon(Icons.event),
                        label: Text('Desde: ${df.format(_from)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTo,
                        icon: const Icon(Icons.event_available),
                        label: Text('Hasta: ${df.format(_to)}'),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 0),

              // 🔸 Lista de sesiones
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _getAllSessions(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text('No hay sesiones en el rango seleccionado.'),
                      );
                    }

                    final sessions = snapshot.data!;
                    return ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, i) {
                        final s = sessions[i];
                        final date = _safeParseDate(s['date']);
                        final formattedDate = (date.year == 0)
                            ? 'Sin fecha'
                            : '${date.day}/${date.month}/${date.year}';
                        final groupName =
                            s['groupName'] ?? s['groupId'] ?? 'Sin grupo';

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: ListTile(
                            title: Text('$groupName — $formattedDate'),
                            subtitle:
                            Text('${s['start'] ?? ''} - ${s['end'] ?? ''}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // ✏️ Editar
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blueAccent),
                                  tooltip: 'Editar pase de lista',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditAttendancePage(
                                          docId: s['id'],
                                          subject: s['groupName'] ?? '',
                                          groupName: groupName,
                                          start: s['start'] ?? '',
                                          end: s['end'] ?? '',
                                          date: date,
                                          records: List<Map<String, dynamic>>.from(
                                              s['records'] ?? []),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                // 🗑️ Eliminar
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  tooltip: 'Eliminar registro',
                                  onPressed: () => _deleteSession(
                                      s['id'], groupName, formattedDate),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),

          // 🧩 Botón inferior para exportar PDF
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Exportar PDF'),
                  onPressed: () async {
                    // 🔹 Menú con opciones
                    final option = await showModalBottomSheet<String>(
                      context: context,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      builder: (_) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(height: 12),
                          const Text('Exportar PDF',
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.bold)),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.assessment_outlined,
                                color: Colors.teal),
                            title: const Text('Exportar resumen general'),
                            onTap: () => Navigator.pop(context, 'general'),
                          ),
                          ListTile(
                            leading: const Icon(Icons.person_outline, color: Colors.indigo),
                            title: const Text('Exportar por alumno'),
                            onTap: () => Navigator.pop(context, 'student'),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    );

                    if (option == 'general') {
                      await AttendancePdf.exportSummaryByStudent(
                        groupId: widget.groupName.replaceAll('|', '_'),
                        subject: null,
                        groupName: widget.displayName ?? widget.groupName,
                        from: _from,
                        to: _to,
                      );
                    } else if (option == 'student') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AttendanceStudentSelectionPage(
                            groupClass: GroupClass(
                              id: widget.groupName.replaceAll('|', '_'),
                              groupName: widget.groupName,
                              subject: '',
                              start: const TimeOfDay(hour: 0, minute: 0),
                              end: const TimeOfDay(hour: 0, minute: 0),
                              students: const [],
                            ),
                            from: _from,
                            to: _to,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}