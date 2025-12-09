import 'dart:typed_data';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'login_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  bool _loading = false;
  String? _error;

  // 🔔 Usuarios pendientes (role == 'pending')
  Stream<QuerySnapshot<Map<String, dynamic>>> _pendingUsersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'pending')
        .snapshots();
  }

  // 👥 Todos los usuarios registrados
  Stream<QuerySnapshot<Map<String, dynamic>>> _allUsersStream() {
    return FirebaseFirestore.instance
        .collection('users')
        .snapshots();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginPage()),
      );
    }
  }

  Future<void> _uploadExcel() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null) return;

      setState(() {
        _loading = true;
        _error = null;
      });

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        bytes = await file.readAsBytes();
      }

      if (bytes == null) {
        throw Exception('No se pudo leer el archivo seleccionado.');
      }

      final excel = Excel.decodeBytes(bytes);
      bool alumnosDetectados = false;

      for (final tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet == null) continue;

        final rows = sheet.rows;
        if (rows.isEmpty) continue;

        // 🔹 Buscar el nombre del grupo dentro de las primeras filas
        String groupName = 'Grupo sin nombre';
        String turno = 'DESCONOCIDO'; // 👈 nuevo
        for (var row in rows.take(20)) {
          for (var cell in row) {
            final value = cell?.value?.toString().trim().toUpperCase() ?? '';

            if (value.startsWith('GRUPO')) {
              final parts = value.split(':');
              if (parts.length > 1) {
                groupName = parts[1].trim();
              }
            }

            // 👇 detectar TURNO: MATUTINO / VESPERTINO
            if (value.startsWith('TURNO')) {
              final parts = value.split(':');
              if (parts.length > 1) {
                turno = parts[1].trim(); // "MATUTINO" o "VESPERTINO"
              }
            }
          }
        }


        int startIndex = -1;
        int colMatricula = -1;
        int colNombre = -1;

        for (int i = 0; i < rows.length; i++) {
          final row = rows[i];
          for (int j = 0; j < row.length; j++) {
            final text = (row[j]?.value?.toString().trim().toLowerCase() ?? '');
            if (text.contains('no. control')) colMatricula = j;
            if (text == 'nombre' || text.contains('nombre')) colNombre = j;
          }
          if (colMatricula != -1 && colNombre != -1) {
            startIndex = i + 1;
            break;
          }
        }

        if (startIndex == -1 || colMatricula == -1 || colNombre == -1) continue;

        List<Map<String, dynamic>> students = [];
        for (int i = startIndex; i < rows.length; i++) {
          final row = rows[i];
          if (row.isEmpty) continue;

          final matricula =
          row.length > colMatricula ? row[colMatricula]?.value?.toString().trim() : '';
          final nombre =
          row.length > colNombre ? row[colNombre]?.value?.toString().trim() : '';

          if ((matricula?.isNotEmpty ?? false) && (nombre?.isNotEmpty ?? false)) {
            students.add({
              'name': nombre,
              'matricula': matricula,
            });
          }
        }

        if (students.isNotEmpty) {
          alumnosDetectados = true;
          await FirebaseFirestore.instance.collection('groups').add({
            'name': groupName,
            'uploaded_by': FirebaseAuth.instance.currentUser!.uid,
            'students': students,
            'created_at': Timestamp.now(),
          });
        }
      }

      if (!alumnosDetectados) {
        throw Exception('No se detectaron alumnos en el archivo.');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listas cargadas exitosamente')),
      );
    } catch (e) {
      setState(() => _error = 'Error al cargar archivo: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteGroup(String id) async {
    await FirebaseFirestore.instance.collection('groups').doc(id).delete();
  }

  // 🔽 Bottom sheet: usuarios pendientes (aprobación)
  Future<void> _showPendingUsersSheet() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Usuarios pendientes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Asigna si cada usuario será administrador o profesor.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _pendingUsersStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No hay usuarios pendientes.',
                              style: TextStyle(fontSize: 14),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final userDoc = docs[index];
                            final data = userDoc.data();
                            final name = data['name'] ?? 'Sin nombre';
                            final email = data['email'] ?? '';
                            final createdAt = data['createdAt'] as Timestamp?;
                            final dateText = createdAt != null
                                ? createdAt.toDate().toLocal().toString()
                                : '';

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      email,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    if (dateText.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Registrado: $dateText',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () async {
                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(userDoc.id)
                                                  .update({'role': 'teacher'});

                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '$name ahora es Profesor.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'No se pudo actualizar: $e',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.school_outlined),
                                          label: const Text('Profesor'),
                                        ),
                                        const SizedBox(width: 8),
                                        FilledButton.icon(
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                            const Color(0xFFD32F2F),
                                          ),
                                          onPressed: () async {
                                            try {
                                              await FirebaseFirestore.instance
                                                  .collection('users')
                                                  .doc(userDoc.id)
                                                  .update({'role': 'admin'});

                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '$name ahora es Administrador.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'No se pudo actualizar: $e',
                                                    ),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          icon: const Icon(Icons.security),
                                          label: const Text('Admin'),
                                        ),
                                      ],
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
            );
          },
        );
      },
    );
  }

  // 🔽 Bottom sheet: gestionar TODOS los usuarios
  Future<void> _showManageUsersSheet() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          initialChildSize: 0.7,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gestionar usuarios',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Consulta todos los usuarios registrados y elimina los que ya no deban tener acceso.\n'
                        'Nota: esto solo elimina el registro en Firestore, no la cuenta de autenticación.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _allUsersStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error: ${snapshot.error}'),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No hay usuarios registrados.',
                              style: TextStyle(fontSize: 14),
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: scrollController,
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final userDoc = docs[index];
                            final data = userDoc.data();
                            final name = data['name'] ?? 'Sin nombre';
                            final email = data['email'] ?? '';
                            final role = data['role'] ?? 'sin rol';
                            final createdAt = data['createdAt'] as Timestamp?;
                            final dateText = createdAt != null
                                ? createdAt.toDate().toLocal().toString()
                                : '';

                            final isSelf = userDoc.id == currentUid;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      email,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    Text(
                                      'Rol: $role',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade700,
                                      ),
                                    ),
                                    if (dateText.isNotEmpty)
                                      Text(
                                        'Creado: $dateText',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: isSelf ? Colors.grey : Colors.red,
                                  ),
                                  onPressed: isSelf
                                      ? () {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No puedes eliminar tu propia cuenta desde aquí.',
                                        ),
                                      ),
                                    );
                                  }
                                      : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text(
                                            'Eliminar usuario'),
                                        content: Text(
                                            '¿Seguro que deseas eliminar a "$name"? '
                                                'Esto solo eliminará su registro en Firestore.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx)
                                                    .pop(false),
                                            child: const Text('Cancelar'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx)
                                                    .pop(true),
                                            child: const Text(
                                              'Eliminar',
                                              style: TextStyle(
                                                  color: Colors.red),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );

                                    if (confirm != true) return;

                                    try {
                                      await FirebaseFirestore.instance
                                          .collection('users')
                                          .doc(userDoc.id)
                                          .delete();

                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'Usuario "$name" eliminado.'),
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                'No se pudo eliminar: $e'),
                                          ),
                                        );
                                      }
                                    }
                                  },
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
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 🔺 Encabezado con logo, título, notificaciones y logout
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo_cetis31.png', width: 60),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Panel de Administración',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      // 🔔 Botón de notificación con badge
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _pendingUsersStream(),
                        builder: (context, snapshot) {
                          final count = snapshot.data?.docs.length ?? 0;

                          return IconButton(
                            onPressed:
                            count == 0 ? null : _showPendingUsersSheet,
                            icon: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                const Icon(Icons.notifications_outlined),
                                if (count > 0)
                                  Positioned(
                                    right: -2,
                                    top: -2,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 18,
                                        minHeight: 18,
                                      ),
                                      child: Center(
                                        child: Text(
                                          count > 9 ? '9+' : '$count',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.red),
                        onPressed: _logout,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 🔘 Fila con Cargar listas + Gestionar usuarios
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _loading ? null : _uploadExcel,
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                          _loading ? 'Cargando...' : 'Cargar listas (.xlsx)',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFD32F2F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _showManageUsersSheet,
                        icon: const Icon(Icons.group_outlined),
                        label: const Text(
                          'Gestionar usuarios',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFD32F2F)),
                          foregroundColor: const Color(0xFFD32F2F),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              if (_error != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              const SizedBox(height: 10),
              const Text(
                'Listas cargadas',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('groups')
                      .orderBy('created_at', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFD32F2F),
                        ),
                      );
                    }
                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                          child: Text('No hay listas cargadas aún'));
                    }
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final group = docs[index];
                        final students =
                        List<Map<String, dynamic>>.from(group['students'] ?? []);
                        return ListTile(
                          title: Text(group['name'] ?? 'Sin nombre'),
                          subtitle: Text(
                            'Alumnos: ${students.length} • Cargado el ${group['created_at'].toDate().toString().substring(0, 16)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteGroup(group.id),
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
