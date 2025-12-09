// lib/pages/teacher_home_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'attendance_page.dart';
import 'attendance_history_page.dart';
import 'grades_capture_page.dart';
import 'grades_history_page.dart';
import '../models.dart';

class TeacherHomePage extends StatefulWidget {
  const TeacherHomePage({super.key});

  @override
  State<TeacherHomePage> createState() => _TeacherHomePageState();
}

class _TeacherHomePageState extends State<TeacherHomePage> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _loading = false;
  String? _error;
  int _selectedIndex = 0; // Para la barra inferior

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  // 🔹 Seleccionar grupo (con filtro por turno)
  Future<void> _selectGroup() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final QuerySnapshot<Map<String, dynamic>> groupsSnap =
      await _firestore.collection('groups').get();

      if (groupsSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay grupos disponibles')),
        );
        return;
      }

      final allDocs = groupsSnap.docs;

      final selected =
      await showDialog<QueryDocumentSnapshot<Map<String, dynamic>>>(
        context: context,
        builder: (ctx) {
          String filtroTurno = 'TODOS'; // TODOS / MATUTINO / VESPERTINO

          return StatefulBuilder(
            builder: (ctx, setStateDialog) {
              final filtered = allDocs.where((doc) {
                final data = doc.data();
                final turno =
                (data['turno'] ?? '').toString().trim().toUpperCase();
                if (filtroTurno == 'TODOS') return true;
                return turno == filtroTurno;
              }).toList();

              return AlertDialog(
                title: const Text('Selecciona un grupo'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text('Turno:'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: filtroTurno,
                            items: const [
                              DropdownMenuItem(
                                value: 'TODOS',
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: 'MATUTINO',
                                child: Text('Matutino'),
                              ),
                              DropdownMenuItem(
                                value: 'VESPERTINO',
                                child: Text('Vespertino'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setStateDialog(() => filtroTurno = value);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text(
                          'No hay grupos para este turno.',
                          style: TextStyle(fontSize: 13),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.maxFinite,
                        height: 300,
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final doc = filtered[i];
                            final data = doc.data();
                            final name = data['name'] ?? 'Sin nombre';
                            final turno = (data['turno'] ?? '').toString();

                            return ListTile(
                              title: Text(name),
                              subtitle: turno.isNotEmpty
                                  ? Text('Turno: $turno')
                                  : null,
                              onTap: () => Navigator.pop(ctx, doc),
                            );
                          },
                        ),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (selected == null) return;

      final uid = _auth.currentUser!.uid;
      final data = selected.data();
      final turno = (data['turno'] ?? '').toString();

      await _firestore
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(selected.id)
          .set({
        'group_id': selected.id,
        'name': data['name'],
        'originalName': data['name'],
        'displayName': data['name'],
        'students': data['students'],
        'created_at': data['created_at'],
        'uploaded_by': data['uploaded_by'],
        'turno': turno,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grupo "${data['name']}" asignado con éxito'),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Error al seleccionar grupo: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // 🗑️ Eliminar grupo
  Future<void> _deleteGroup(String groupId, String groupName) async {
    final uid = _auth.currentUser!.uid;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text(
          '¿Seguro que deseas eliminar "$groupName"?\n\n'
              'Esto eliminará también todo su historial de asistencias y calificaciones.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar todo'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final teacherRef = _firestore.collection('teachers').doc(uid);

      await teacherRef.collection('assigned_groups').doc(groupId).delete();

      // Borrar asistencias y calificaciones del grupo
      final attendanceRef =
      teacherRef.collection('attendance').doc(groupName).collection(
        'sessions',
      );
      final gradesRef =
      teacherRef.collection('grades').doc(groupName).collection(
        'activities',
      );

      final sessionsSnap = await attendanceRef.get();
      for (var doc in sessionsSnap.docs) {
        await attendanceRef.doc(doc.id).delete();
      }

      final gradesSnap = await gradesRef.get();
      for (var doc in gradesSnap.docs) {
        await gradesRef.doc(doc.id).delete();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grupo "$groupName" eliminado con su historial.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar grupo: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  // ✏️ Editar nombre visual
  Future<void> _editGroupName(String groupId, String currentDisplay) async {
    final controller = TextEditingController(text: currentDisplay);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar nombre del grupo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nuevo nombre visual',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentDisplay) {
      return;
    }

    try {
      final uid = _auth.currentUser!.uid;
      await _firestore
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(groupId)
          .update({'displayName': newName});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nombre visual cambiado a "$newName"')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al editar nombre: $e')),
      );
    }
  }

  // 🔹 Cuerpo de asistencia
  Widget _buildAttendanceBody() {
    final uid = _auth.currentUser!.uid;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(
                _loading ? 'Cargando...' : 'Seleccionar grupo',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: Colors.white),
              ),
              onPressed: _loading ? null : _selectGroup,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('teachers')
                  .doc(uid)
                  .collection('assigned_groups')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                      child: Text('No has seleccionado ningún grupo.'));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final group = docs[i];
                    final data =
                        group.data() as Map<String, dynamic>? ?? <String, dynamic>{};

                    final groupName =
                        data['displayName'] ?? data['name'] ?? 'Sin nombre';
                    final originalName =
                        data['originalName'] ?? data['name'] ?? groupName;
                    final rawStudents = data['students'] ?? [];
                    final turno = (data['turno'] ?? '').toString();

                    final List<Student> students = [];
                    if (rawStudents is List) {
                      for (var s in rawStudents) {
                        if (s is String) {
                          students.add(Student(id: '', name: s));
                        } else if (s is Map) {
                          students.add(Student(
                            id: s['matricula']?.toString() ?? '',
                            name: s['name']?.toString() ?? '',
                          ));
                        }
                      }
                    }

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDF0F1),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editGroupName(group.id, groupName);
                                  } else if (value == 'delete') {
                                    _deleteGroup(group.id, originalName);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.black54),
                                        SizedBox(width: 8),
                                        Text('Editar'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_outline,
                                            color: Colors.redAccent),
                                        SizedBox(width: 8),
                                        Text('Eliminar'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Alumnos: ${students.length}' +
                                (turno.isNotEmpty ? ' • Turno: $turno' : ''),
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AttendancePage(
                                          groupClass: GroupClass(
                                            id: group.id,
                                            groupName: originalName,
                                            subject: 'Materia no especificada',
                                            start: const TimeOfDay(
                                                hour: 7, minute: 0),
                                            end: const TimeOfDay(
                                                hour: 8, minute: 0),
                                            students: students,
                                            turno: turno,
                                            dia: '',
                                          ),
                                          initialDate: DateTime.now(),
                                        ),
                                      ),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFD32F2F),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text('Tomar Lista $groupName'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            AttendanceHistoryPage(
                                              groupName: originalName,
                                              displayName: groupName,
                                            ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.history),
                                  label: const Text('Historial'),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Color(0xFFD32F2F)),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 🔹 Cuerpo de calificaciones
  Widget _buildGradesBody() {
    final uid = _auth.currentUser!.uid;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('teachers')
            .doc(uid)
            .collection('assigned_groups')
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No tienes grupos asignados.'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final group = docs[i];
              final data =
                  group.data() as Map<String, dynamic>? ?? <String, dynamic>{};

              final groupName =
                  data['displayName'] ?? data['name'] ?? 'Sin nombre';
              final originalName =
                  data['originalName'] ?? data['name'] ?? groupName;
              final rawStudents = data['students'] ?? [];
              final turno = (data['turno'] ?? '').toString();

              final List<Student> students = [];
              if (rawStudents is List) {
                for (var s in rawStudents) {
                  if (s is String) {
                    students.add(Student(id: '', name: s));
                  } else if (s is Map) {
                    students.add(Student(
                      id: s['matricula']?.toString() ?? '',
                      name: s['name']?.toString() ?? '',
                    ));
                  }
                }
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDF0F1),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            groupName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Alumnos: ${students.length}' +
                          (turno.isNotEmpty ? ' • Turno: $turno' : ''),
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GradesCapturePage(
                                    groupClass: GroupClass(
                                      id: group.id,
                                      groupName: originalName,
                                      subject: 'Materia no especificada',
                                      start: const TimeOfDay(
                                          hour: 7, minute: 0),
                                      end: const TimeOfDay(
                                          hour: 8, minute: 0),
                                      students: students,
                                      turno: turno,
                                      dia: '',
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit_note),
                            label: Text('Capturar $groupName'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD32F2F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => GradesHistoryPage(
                                    groupClass: GroupClass(
                                      id: group.id,
                                      groupName: originalName,
                                      subject: 'Materia no especificada',
                                      start: const TimeOfDay(
                                          hour: 7, minute: 0),
                                      end: const TimeOfDay(
                                          hour: 8, minute: 0),
                                      students: students,
                                      turno: turno,
                                      dia: '',
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.history),
                            label: const Text('Historial'),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFD32F2F)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Control de asistencias CETIS 31',
          style:
          TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child:
        _selectedIndex == 0 ? _buildAttendanceBody() : _buildGradesBody(),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.white70,
        onTap: (i) => setState(() => _selectedIndex = i),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.assignment),
            label: 'Asistencia',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grade),
            label: 'Calificaciones',
          ),
        ],
      ),
    );
  }
}
