import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;

import '../models.dart';
import '../local_groups.dart' as LG;
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
    final items = await LG.LocalGroups.listGroups();
    if (!mounted) return;
    setState(() => _groups = items);
  }

  // ===== Generar PDF con LOGO y calificaciones =====
  Future<void> _exportGradesPdf(GroupClass group) async {
    try {
      final groupId = LG.groupKeyOf(group);
      final boxName = 'grades::$groupId';
      if (!Hive.isBoxOpen(boxName)) {
        await Hive.openBox(boxName);
      }
      final box = Hive.box(boxName);

      final students = await LG.LocalGroups.listStudents(groupId: groupId);
      students.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );

      // Carga de logo desde assets (mismo del dashboard)
      final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

      final doc = pw.Document();

      final rows = <List<String>>[];
      rows.add(<String>['#', 'Matrícula', 'Nombre', 'Calificación']);
      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        final grade = box.get(s.id);
        rows.add([
          '${i + 1}',
          s.id,
          s.name,
          grade == null ? '' : grade.toString(),
        ]);
      }

      doc.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(28),
          build:
              (ctx) => [
                // Encabezado con logo + título
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 48,
                      height: 48,
                      decoration: pw.BoxDecoration(
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                    ),
                    pw.SizedBox(width: 12),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Sistema CETIS 31',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          'Historial de calificaciones',
                          style: const pw.TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  '${group.subject} — ${group.groupName}  (${group.turno ?? ''} ${group.dia ?? ''})',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 10),
                pw.TableHelper.fromTextArray(
                  data: rows,
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellStyle: const pw.TextStyle(fontSize: 10),
                  headerDecoration: pw.BoxDecoration(
                    color: pdf.PdfColors.grey300, // o pdf.PdfColor.fromInt(0xFFF2F2F2)
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  cellAlignment: pw.Alignment.centerLeft,
                  headerAlignment: pw.Alignment.centerLeft,
                  border: null,
  // rowDecoration: pw.BoxDecoration(), // opcional
                ),

                pw.SizedBox(height: 12),
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    'Total alumnos: ${students.length}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
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
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        _groups.where((g) {
          final q = _query.toLowerCase();
          return g.subject.toLowerCase().contains(q) ||
              g.groupName.toLowerCase().contains(q) ||
              (g.turno ?? '').toLowerCase().contains(q) ||
              (g.dia ?? '').toLowerCase().contains(q);
        }).toList();

    final Map<String, List<GroupClass>> grouped = {};
    for (final g in filtered) {
      final key = '${g.subject}|||${g.groupName}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(g);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Calificaciones'),
            Text(
              'Bienvenido, ${widget.teacherName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar grupo, materia, turno o día…',
              ),
            ),
          ),
          const Divider(height: 0),
          Expanded(
            child:
                grouped.isEmpty
                    ? const Center(child: Text('Aún no hay grupos importados'))
                    : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      itemCount: grouped.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final key = grouped.keys.elementAt(i);
                        final list = grouped[key]!;
                        final subject = list.first.subject;
                        final groupName = list.first.groupName;
                        return _GradesGroupCard(
                          subject: subject,
                          groupName: groupName,
                          groups: list,
                          onCapture: (g) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder:
                                    (_) => GradesCapturePage(groupClass: g),
                              ),
                            );
                          },
                          onExportPdf: (g) => _exportGradesPdf(g),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

// Tarjeta “gemela” de tu dashboard: Capturar / Generar PDF
class _GradesGroupCard extends StatelessWidget {
  final String subject;
  final String groupName;
  final List<GroupClass> groups;
  final ValueChanged<GroupClass> onCapture;
  final ValueChanged<GroupClass> onExportPdf;

  const _GradesGroupCard({
    required this.subject,
    required this.groupName,
    required this.groups,
    required this.onCapture,
    required this.onExportPdf,
  });

  @override
  Widget build(BuildContext context) {
    final GroupClass main = groups.first;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        groupName,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            groups.map((g) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.auto_awesome, size: 16),
                                    const SizedBox(width: 4),
                                    Text(g.turno ?? ''),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.event_note, size: 16),
                                    const SizedBox(width: 4),
                                    Text(g.dia ?? ''),
                                  ],
                                ),
                              );
                            }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onCapture(main),
                    icon: const Icon(Icons.grade_outlined),
                    label: Text('Capturar $groupName'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onExportPdf(main),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Generar PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
