import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models.dart';
import '../services/attendance_service.dart';

class AttendancePage extends StatefulWidget {
  static const route = '/attendance';
  final GroupClass groupClass;
  final DateTime initialDate;

  const AttendancePage({
    super.key,
    required this.groupClass,
    required this.initialDate,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  DateTime _date = DateTime.now();
  List<Student> _students = [];
  bool _loading = true;
  String _query = '';

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _loadStudentsFromAssignedGroup();
  }

  Future<void> _loadStudentsFromAssignedGroup() async {
    try {
      setState(() => _loading = true);

      final uid = _auth.currentUser!.uid;
      final docSnap = await _firestore
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(widget.groupClass.id)
          .get();

      if (!docSnap.exists) {
        throw Exception('El grupo no existe o no tiene alumnos.');
      }

      final studentsData =
          List<Map<String, dynamic>>.from(docSnap.data()!['students']);
      _students = studentsData
          .map((s) => Student(
                id: s['matricula'] ?? '',
                name: s['name'] ?? '',
                status: AttendanceStatus.none,
              ))
          .toList();

      setState(() => _loading = false);
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar alumnos: $e')),
      );
    }
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    try {
      final uid = _auth.currentUser!.uid;

      await AttendanceService.instance.saveSessionToFirestore(
        groupId: widget.groupClass.id,
        subject: widget.groupClass.subject,
        groupName: widget.groupClass.groupName,
        start: _fmtTime(widget.groupClass.start),
        end: _fmtTime(widget.groupClass.end),
        date: _date,
        records: _students
            .map((s) => {
                  'studentId': s.id,
                  'name': s.name,
                  'status': switch (s.status) {
                    AttendanceStatus.present => 'present',
                    AttendanceStatus.late => 'late',
                    AttendanceStatus.absent => 'absent',
                    _ => 'none',
                  },
                })
            .toList(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista guardada con éxito')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d/M/yyyy');
    final filtered = _query.isEmpty
        ? _students
        : _students
            .where((s) =>
                s.name.toLowerCase().contains(_query.toLowerCase()) ||
                s.id.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupClass.subject.isEmpty
            ? 'Materia no especificada'
            : widget.groupClass.subject),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(10),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Text(
              '${widget.groupClass.groupName}  •  ${_fmtTime(widget.groupClass.start)} - ${_fmtTime(widget.groupClass.end)}\n${df.format(_date)}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar estudiante...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('No hay alumnos.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            return Card(
                              color: Colors.pink.shade50,
                              margin: const EdgeInsets.all(8),
                              child: ListTile(
                                title: Text(s.name),
                                subtitle: Text('Matrícula: ${s.id}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check_circle),
                                      color:
                                          s.status == AttendanceStatus.present
                                              ? Colors.green
                                              : Colors.grey,
                                      onPressed: () => setState(() {
                                        s.status = AttendanceStatus.present;
                                      }),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.access_time),
                                      color: s.status == AttendanceStatus.late
                                          ? Colors.orange
                                          : Colors.grey,
                                      onPressed: () => setState(() {
                                        s.status = AttendanceStatus.late;
                                      }),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.cancel),
                                      color: s.status == AttendanceStatus.absent
                                          ? Colors.red
                                          : Colors.grey,
                                      onPressed: () => setState(() {
                                        s.status = AttendanceStatus.absent;
                                      }),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(Icons.save),
                    label: const Text('Guardar lista'),
                    onPressed: _save,
                  ),
                ),
              ],
            ),
    );
  }
}
