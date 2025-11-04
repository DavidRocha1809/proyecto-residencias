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
        for (var row in rows.take(20)) {
          for (var cell in row) {
            final value = cell?.value?.toString().trim().toUpperCase() ?? '';
            if (value.startsWith('GRUPO')) {
              final parts = value.split(':');
              if (parts.length > 1) {
                groupName = parts[1].trim();
              }
            }
          }
        }

        // 🔍 Buscar encabezados: “NO. CONTROL” y “NOMBRE”
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

        // 🔹 Leer alumnos desde el Excel
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

        // 🔹 Guardar en Firestore
        if (students.isNotEmpty) {
          alumnosDetectados = true;
          await FirebaseFirestore.instance.collection('groups').add({
            'name': groupName, // ❗ mantenemos tu lógica original
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Image.asset('assets/images/logo_cetis31.png', width: 60),
                  const Text(
                    'Panel de Administración',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: Colors.black87,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.red),
                    onPressed: _logout,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
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
