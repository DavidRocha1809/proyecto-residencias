// lib/pages/edit_attendance_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum _St { present, late, absent }

class EditAttendancePage extends StatefulWidget {
  const EditAttendancePage({
    super.key,
    required this.docId,
    required this.subject,
    required this.groupName,
    required this.start,
    required this.end,
    required this.date,
    required this.records,
  });

  final String docId;
  final String subject;
  final String groupName;
  final String start;
  final String end;
  final DateTime date;
  final List<Map<String, dynamic>> records;

  @override
  State<EditAttendancePage> createState() => _EditAttendancePageState();
}

class _EditAttendancePageState extends State<EditAttendancePage> {
  late List<_Row> _rows;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.records
        .map((e) => _Row(
              id: e['studentId'] ?? '',
              name: e['name'] ?? '',
              status: _parseStatus(e['status']),
            ))
        .toList();
  }

  _St _parseStatus(dynamic s) {
    switch (s) {
      case 'present':
        return _St.present;
      case 'late':
        return _St.late;
      case 'absent':
        return _St.absent;
      default:
        return _St.present;
    }
  }

  String _statusToString(_St s) {
    switch (s) {
      case _St.present:
        return 'present';
      case _St.late:
        return 'late';
      case _St.absent:
        return 'absent';
    }
  }

  Future<void> _saveChanges() async {
    setState(() => _saving = true);
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;

    final updatedRecords = _rows
        .map((r) => {
              'studentId': r.id,
              'name': r.name,
              'status': _statusToString(r.status),
            })
        .toList();

    try {
      await firestore
          .collection('teachers')
          .doc(uid)
          .collection('attendance')
          .doc(widget.docId)
          .update({'records': updatedRecords});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cambios guardados correctamente.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar cambios: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _rows
        .where((r) =>
            r.name.toLowerCase().contains(_query.toLowerCase()) ||
            r.id.contains(_query))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(10),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
      body: Column(
        children: [
          // 🔹 Buscador
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar alumno...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),

          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final r = filtered[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ListTile(
                    title: Text(r.name),
                    subtitle: Text(r.id),
                    trailing: ToggleButtons(
                      borderRadius: BorderRadius.circular(12),
                      isSelected: [
                        r.status == _St.present,
                        r.status == _St.late,
                        r.status == _St.absent
                      ],
                      onPressed: (index) {
                        setState(() {
                          r.status = _St.values[index];
                        });
                      },
                      children: const [
                        Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.check_circle,
                                color: Colors.green)),
                        Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.access_time,
                                color: Colors.orange)),
                        Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child:
                                Icon(Icons.cancel, color: Colors.redAccent)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),

      // 🔹 Botón Guardar
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('Guardar cambios'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _saving ? null : _saveChanges,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// 🔹 Modelo interno de fila
// ============================================================
class _Row {
  final String id;
  final String name;
  _St status;
  _Row({required this.id, required this.name, required this.status});
}
