import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';
import 'attendance_page.dart';
import 'grades_history_page.dart';
import '../models.dart'; // ✅ Import necesario para usar GroupClass

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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginPage()));
    }
  }

  Future<void> _selectGroup() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      // 🔹 Obtener los grupos cargados por el admin
      final groupsSnap = await _firestore.collection('groups').get();
      if (groupsSnap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay grupos disponibles')),
        );
        return;
      }

      // Mostrar diálogo de selección
      final selected = await showDialog<QueryDocumentSnapshot>(
        context: context,
        builder: (ctx) {
          return SimpleDialog(
            title: const Text('Selecciona un grupo'),
            children:
                groupsSnap.docs.map((doc) {
                  return SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, doc),
                    child: Text(doc['name'] ?? 'Sin nombre'),
                  );
                }).toList(),
          );
        },
      );

      if (selected == null) return;

      // 🔹 Guardar el grupo seleccionado en el perfil del profesor
      final uid = _auth.currentUser!.uid;
      await _firestore
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(selected.id)
          .set({
            'group_id': selected.id,
            'name': selected['name'],
            'students': selected['students'],
            'created_at': selected['created_at'],
            'uploaded_by': selected['uploaded_by'],
          });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Grupo "${selected['name']}" asignado con éxito'),
        ),
      );
    } catch (e) {
      setState(() => _error = 'Error al seleccionar grupo: $e');
    } finally {
      setState(() => _loading = false);
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
              // 🔍 Botón para seleccionar grupo
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
                Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),

              const SizedBox(height: 16),

              // 🔹 Mostrar grupos asignados como tarjetas
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream:
                      _firestore
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
                        final groupName = group['name'] ?? 'Sin nombre';
                        final students = List<String>.from(
                          group['students'] ?? [],
                        );

                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF0F1),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                groupName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black87,
                                ),
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
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => AttendancePage(
                                                  groupClass: GroupClass(
                                                    groupName: groupName,
                                                    subject:
                                                        'Materia no especificada',
                                                    start: const TimeOfDay(
                                                      hour: 7,
                                                      minute: 0,
                                                    ),
                                                    end: const TimeOfDay(
                                                      hour: 8,
                                                      minute: 0,
                                                    ),
                                                    students:
                                                        students
                                                            .map(
                                                              (s) => Student(
                                                                id: s,
                                                                name: s,
                                                              ),
                                                            )
                                                            .toList(),
                                                    turno: 'Vespertino',
                                                    dia: '',
                                                  ),
                                                  initialDate: DateTime.now(),
                                                ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFFD32F2F,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                            builder:
                                                (_) => GradesHistoryPage(
                                                  groupClass: GroupClass(
                                                    groupName: groupName,
                                                    subject:
                                                        'Materia no especificada',
                                                    turno: 'Vespertino',
                                                    dia: '',
                                                    start: const TimeOfDay(
                                                      hour: 7,
                                                      minute: 0,
                                                    ),
                                                    end: const TimeOfDay(
                                                      hour: 8,
                                                      minute: 0,
                                                    ),
                                                    students:
                                                        students
                                                            .map(
                                                              (s) => Student(
                                                                id: s,
                                                                name: s,
                                                              ),
                                                            )
                                                            .toList(),
                                                  ),
                                                ),
                                          ),
                                        );
                                      },
                                      icon: const Icon(Icons.history),
                                      label: const Text('Historial'),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                          color: Color(0xFFD32F2F),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
