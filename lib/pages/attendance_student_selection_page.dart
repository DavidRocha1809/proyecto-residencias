import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../utils/attendance_pdf.dart';

class AttendanceStudentSelectionPage extends StatefulWidget {
  final GroupClass groupClass;
  final DateTime from;
  final DateTime to;

  const AttendanceStudentSelectionPage({
    super.key,
    required this.groupClass,
    required this.from,
    required this.to,
  });

  @override
  State<AttendanceStudentSelectionPage> createState() =>
      _AttendanceStudentSelectionPageState();
}

class _AttendanceStudentSelectionPageState
    extends State<AttendanceStudentSelectionPage> {
  bool _loading = true;
  List<Student> _students = [];
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    setState(() => _loading = true);
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Usuario no autenticado.');

      final docSnap = await _firestore
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(widget.groupClass.id)
          .get();

      final data = docSnap.data();
      if (data == null) throw Exception('No se encontraron alumnos.');

      final students = List<Map<String, dynamic>>.from(data['students'] ?? [])
          .map((s) => Student(
                id: s['matricula'] ?? '',
                name: s['name'] ?? '',
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _students = students;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar alumnos: $e')),
      );
    }
  }

  Future<void> _exportForStudent(Student s) async {
    try {
      await AttendancePdf.exportStudentReport(
        groupId: widget.groupClass.id,
        student: s,
        subject: widget.groupClass.subject,
        groupName: widget.groupClass.groupName,
        from: widget.from,
        to: widget.to,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al generar PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Exportar asistencia por alumno'),
            Text(
              'Del ${df.format(widget.from)} al ${df.format(widget.to)}',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _students.length,
              itemBuilder: (_, i) {
                final s = _students[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: Colors.pink.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(s.name,
                        style:
                            const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('Matrícula: ${s.id}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.picture_as_pdf,
                          color: Colors.redAccent),
                      onPressed: () => _exportForStudent(s),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
