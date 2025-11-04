import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'attendance_page.dart';
import 'grades_history_page.dart';
import '../models.dart'; // ✅ Import necesario para usar GroupClass y Student

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

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  // 🔹 Seleccionar grupo (crea con campos originales)
  Future<void> _selectGroup() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final groupsSnap = await _firestore.collection('groups').get();
      if (groupsSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay grupos disponibles')),
        );
        return;
      }

      final selected = await showDialog<QueryDocumentSnapshot>(
        context: context,
        builder: (ctx) {
          return SimpleDialog(
            title: const Text('Selecciona un grupo'),
            children: groupsSnap.docs
                .map(
                  (doc) => SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, doc),
                    child: Text(doc['name'] ?? 'Sin nombre'),
                  ),
                )
                .toList(),
          );
        },
      );

      if (selected == null) return;

      final uid = _auth.currentUser!.uid;
      await _firestore
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(selected.id)
          .set({
        'group_id': selected.id,
        'name': selected['name'], // nombre real
        'originalName': selected['name'],
        'displayName': selected['name'], // nombre visual
        'students': selected['students'],
        'created_at': selected['created_at'],
        'uploaded_by': selected['uploaded_by'],
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Grupo "${selected['name']}" asignado con éxito')),
      );
    } catch (e) {
      setState(() => _error = 'Error al seleccionar grupo: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  // 🗑️ Eliminar grupo + historial
  Future<void> _deleteGroup(String groupId, String groupName) async {
    final uid = _auth.currentUser!.uid;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar grupo'),
        content: Text(
          '¿Seguro que deseas eliminar "$groupName"?\n\n'
          'Esto eliminará también todo su historial de asistencias.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar todo')),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final teacherRef = _firestore.collection('teachers').doc(uid);

      // 1️⃣ Eliminar grupo asignado
      await teacherRef.collection('assigned_groups').doc(groupId).delete();

      // 2️⃣ Eliminar sesiones de asistencia
      final sessionsRef = teacherRef
          .collection('attendance')
          .doc(groupName)
          .collection('sessions');

      final sessionsSnap = await sessionsRef.get();
      for (var doc in sessionsSnap.docs) {
        await sessionsRef.doc(doc.id).delete();
      }

      // 3️⃣ Eliminar documento principal del grupo en attendance
      await teacherRef.collection('attendance').doc(groupName).delete();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grupo "$groupName" y su historial fueron eliminados.'),
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

  // ✏️ Editar nombre visual (solo interfaz)
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentDisplay) return;

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

  @override
  Widget build(BuildContext context) {
    final uid = _auth.currentUser!.uid;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text(
          'Sistema CETIS 31',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(
                    _loading ? 'Cargando...' : 'Seleccionar grupo',
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
                Text(_error!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13)),

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
                        child: Text('No has seleccionado ningún grupo.'),
                      );
                    }

                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final group = docs[i];
                        final data = group.data() as Map<String, dynamic>? ?? {};

                        final groupName = data['displayName'] ?? data['name'] ?? 'Sin nombre';
                        final originalName = data['originalName'] ?? data['name'] ?? groupName;
                        final rawStudents = data['students'] ?? [];

                        // ✅ Soporte para alumnos con matrícula
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
                              // 🔹 Encabezado y menú
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
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit, color: Colors.black54),
                                            SizedBox(width: 8),
                                            Text('Editar'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline, color: Colors.redAccent),
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
                                'Alumnos: ${students.length}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 10),

                              // 🔹 Botones de acción
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
                                                groupName: originalName, // siempre el real
                                                subject: 'Materia no especificada',
                                                start: const TimeOfDay(hour: 7, minute: 0),
                                                end: const TimeOfDay(hour: 8, minute: 0),
                                                students: students,
                                                turno: 'Vespertino',
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
                                            builder: (_) => GradesHistoryPage(
                                              groupClass: GroupClass(
                                                groupName: originalName, // real
                                                subject: 'Materia no especificada',
                                                turno: 'Vespertino',
                                                dia: '',
                                                start: const TimeOfDay(hour: 7, minute: 0),
                                                end: const TimeOfDay(hour: 8, minute: 0),
                                                students: students,
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
