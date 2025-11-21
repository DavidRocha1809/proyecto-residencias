import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models.dart';
import 'grades_capture_page.dart';

class GradesDashboardPage extends StatefulWidget {
  final String teacherName;
  const GradesDashboardPage({super.key, this.teacherName = 'Docente'});

  @override
  State<GradesDashboardPage> createState() => _GradesDashboardPageState();
}

class _GradesDashboardPageState extends State<GradesDashboardPage> {
  String _query = '';
  List<GroupClass> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('No hay usuario autenticado');

      final snap = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(uid)
          .collection('groups')
          .get();

      final list = snap.docs.map((d) {
        final data = d.data();
        return GroupClass(
          id: d.id, // ✅ Agregado
          groupName: data['groupName'] ?? d.id,
          subject: data['subject'] ?? 'Materia no especificada',
          start: const TimeOfDay(hour: 7, minute: 0),
          end: const TimeOfDay(hour: 8, minute: 0),
          students: const [],
          turno: data['turno'],
          dia: data['dia'],
        );
      }).toList();

      if (!mounted) return;
      setState(() => _groups = list);
    } catch (e) {
      debugPrint('❌ Error cargando grupos: $e');
    }
  }

  Future<void> _exportGradesPdf(GroupClass group) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('No autenticado');

      // 🔹 Obtener alumnos
      final studentsSnap = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(uid)
          .collection('groups')
          .doc(group.id)
          .collection('students')
          .get();

      final students = studentsSnap.docs
          .map((d) => Student(id: d.id, name: d['name'] ?? ''))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      // 🔹 Obtener calificaciones
      final gradesSnap = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(uid)
          .collection('grades')
          .doc(group.id)
          .collection('activities')
          .get();

      final Map<String, dynamic> latestGrades = {};
      for (final doc in gradesSnap.docs) {
        final grades = Map<String, dynamic>.from(doc['grades'] ?? {});
        latestGrades.addAll(grades);
      }

      final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

      final doc = pw.Document();
      final rows = <List<String>>[
        ['#', 'Matrícula', 'Nombre', 'Calificación']
      ];

      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        final grade = latestGrades[s.id] ?? '';
        rows.add(['${i + 1}', s.id, s.name, grade.toString()]);
      }

      doc.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => [
            pw.Row(
              children: [
                pw.Container(width: 48, height: 48, child: pw.Image(logoImage)),
                pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('CETIS 31 - Calificaciones',
                        style: pw.TextStyle(
                            fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('${group.subject} — ${group.groupName}',
                        style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(
              data: rows,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration: pw.BoxDecoration(color: pdf.PdfColors.grey300),
            ),
          ],
        ),
      );

      final bytes = await doc.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'calificaciones_${group.groupName}.pdf',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _groups.where((g) {
      final q = _query.toLowerCase();
      return g.subject.toLowerCase().contains(q) ||
          g.groupName.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calificaciones'),
        actions: [
          IconButton(onPressed: _loadGroups, icon: const Icon(Icons.refresh))
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar grupo o materia…',
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No hay grupos cargados'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final g = filtered[i];
                      return Card(
                        child: ListTile(
                          title: Text(g.groupName),
                          subtitle: Text(g.subject),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        GradesCapturePage(groupClass: g),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                onPressed: () => _exportGradesPdf(g),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
