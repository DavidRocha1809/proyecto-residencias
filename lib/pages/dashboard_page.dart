import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:flutter/services.dart' show rootBundle;

import '../models.dart';
import '../local_groups.dart' as LG;

import 'attendance_page.dart';
import 'sessions_page.dart';
import 'grades_capture_page.dart';
import 'grades_history_page.dart'; // ⬅ nuevo

class DashboardPage extends StatefulWidget {
  static const route = '/dashboard';
  final String teacherName;
  const DashboardPage({super.key, this.teacherName = 'Docente'});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedTab = 0; // 0 = Pase de lista, 1 = Calificaciones
  String _query = '';
  List<GroupClass> _groups = [];

  @override
  void initState() {
    super.initState();
    _refreshGroups();
  }

  Future<void> _refreshGroups() async {
    final items = await LG.LocalGroups.listGroups();
    if (!mounted) return;
    setState(() => _groups = items);
  }

  // ===================== IMPORTAR CSV =====================
  Future<void> _importGroupsAndStudentsFromCsv(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;

      final raw = utf8.decode(picked.files.single.bytes!);
      final text = raw.replaceAll('\uFEFF', '');
      final rows = const CsvToListConverter(
        shouldParseNumbers: false,
        eol: '\n',
      ).convert(text);

      if (rows.isEmpty) {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('CSV vacío')));
        return;
      }

      final header = rows.first.map((e) => e.toString().trim()).toList();
      Map<String, int> col = {};
      for (final h in [
        'groupName','subject','start','end','turno','dia','matricula','name'
      ]) {
        final i = header.indexOf(h);
        if (i < 0) {
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text('Falta columna "$h"')));
          return;
        }
        col[h] = i;
      }

      final Map<String, Map<String, dynamic>> groups = {};
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.length < header.length) continue;

        final groupName = row[col['groupName']!]!.toString().trim();
        final subject   = row[col['subject']!]!.toString().trim();
        final start     = row[col['start']!]!.toString().trim();
        final end       = row[col['end']!]!.toString().trim();
        final turno     = row[col['turno']!]!.toString().trim();
        final dia       = row[col['dia']!]!.toString().trim();
        final matricula = row[col['matricula']!]!.toString().trim();
        final name      = row[col['name']!]!.toString().trim();

        if ([groupName,subject,turno,dia,matricula,name].any((s) => s.isEmpty)) {
          continue;
        }

        final key = '$groupName|$subject|$turno|$dia';
        groups.putIfAbsent(key, () => {
          'groupName': groupName,
          'subject': subject,
          'turno': turno,
          'dia': dia,
          'start': start,
          'end': end,
          'students': <Map<String, dynamic>>[],
        });

        (groups[key]!['students'] as List<Map<String, dynamic>>).add({
          'studentId': matricula,
          'name': name,
        });
      }

      for (final entry in groups.values) {
        final groupName = entry['groupName'] as String;
        final subject   = entry['subject'] as String;
        final turno     = entry['turno'] as String;
        final dia       = entry['dia'] as String;
        final start     = entry['start'] as String?;
        final end       = entry['end'] as String?;
        final students  = (entry['students'] as List).cast<Map<String, dynamic>>();

        final groupId = LG.groupKeyFromParts(groupName, turno, dia);

        await LG.LocalGroups.upsertGroup(
          groupId: groupId,
          groupName: groupName,
          subject: subject,
          turno: turno,
          dia: dia,
          start: start,
          end: end,
        );

        final byId = <String, Map<String, dynamic>>{};
        for (final s in students) {
          final sid = (s['studentId'] ?? '').toString().trim();
          if (sid.isEmpty) continue;
          byId[sid] = s;
        }
        await LG.LocalGroups.upsertStudentsBulk(
          groupId: groupId,
          students: byId.values.toList(),
        );
      }

      await _refreshGroups();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Importación completa')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error al importar: $e')));
    }
  }

  // (sigue existiendo tu exportación directa si algún día la quieres usar)
  Future<void> _exportGradesPdf(GroupClass group) async {
    try {
      final groupId = LG.groupKeyOf(group);
      final boxName = 'grades::$groupId';
      if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
      final box = Hive.box(boxName);

      final students = await LG.LocalGroups.listStudents(groupId: groupId)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
      final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

      final rows = <List<String>>[
        <String>['#','Matrícula','Nombre','Calificación'],
      ];
      for (int i = 0; i < students.length; i++) {
        final s = students[i];
        final grade = box.get(s.id);
        rows.add(['${i+1}', s.id, s.name, grade?.toString() ?? '']);
      }

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(children: [
            pw.SizedBox(width: 48, height: 48, child: pw.Image(logoImage)),
            pw.SizedBox(width: 12),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Sistema CETIS 31', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Historial de calificaciones', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 10),
          pw.Text('${group.subject} — ${group.groupName}  (${group.turno ?? ''} ${group.dia ?? ''})', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(
              color: pdf.PdfColors.grey300,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            border: null,
          ),
        ],
      ));

      final bytes = await doc.save();
      await Printing.sharePdf(bytes: bytes, filename: 'calificaciones_${group.groupName}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  Widget _buildCards({
    required List<GroupClass> groups,
    required bool isGradesMode,
  }) {
    final filtered = groups.where((g) {
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

    if (grouped.isEmpty) {
      return const Center(child: Text('Aún no hay grupos importados'));
    }

    return RefreshIndicator(
      onRefresh: _refreshGroups,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        itemCount: grouped.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final key = grouped.keys.elementAt(i);
          final list = grouped[key]!;
          final subject = list.first.subject;
          final groupName = list.first.groupName;

          return _GroupCard(
            subject: subject,
            groupName: groupName,
            groups: list,
            isGradesMode: isGradesMode,
            onPrimary: (g) {
              if (isGradesMode) {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => GradesCapturePage(groupClass: g),
                ));
              } else {
                final now = DateTime.now();
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AttendancePage(
                    groupClass: g,
                    initialDate: DateTime(now.year, now.month, now.day),
                  ),
                ));
              }
            },
            onSecondary: (g) {
              if (isGradesMode) {
                // ⬅ ahora abre el historial (no PDF directo)
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => GradesHistoryPage(groupClass: g),
                ));
              } else {
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SessionsPage(groups: [g], autoSkipSingle: true),
                ));
              }
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isGrades = _selectedTab == 1;

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Image.asset('assets/images/logo_cetis31.png', width: 32, height: 32),
        ),
        leadingWidth: 56,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isGrades ? 'Calificaciones' : 'Sistema CETIS 31',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('Bienvenido, ${widget.teacherName}',
                style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Importar CSV',
            icon: const Icon(Icons.upload_file),
            onPressed: () => _importGroupsAndStudentsFromCsv(context),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              const storage = FlutterSecureStorage();
              await storage.delete(key: 'auth_email');
              await storage.delete(key: 'auth_password');
              await FirebaseAuth.instance.signOut();
            },
          ),
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
                hintText: 'Buscar grupo, materia, turno o día…',
              ),
            ),
          ),
          const Divider(height: 0),
          Expanded(child: _buildCards(groups: _groups, isGradesMode: isGrades)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (i) => setState(() => _selectedTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Pase de lista',
          ),
          NavigationDestination(
            icon: Icon(Icons.grade_outlined),
            selectedIcon: Icon(Icons.grade),
            label: 'Calificaciones',
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final String subject;
  final String groupName;
  final List<GroupClass> groups;
  final bool isGradesMode;
  final ValueChanged<GroupClass> onPrimary;
  final ValueChanged<GroupClass> onSecondary;

  const _GroupCard({
    required this.subject,
    required this.groupName,
    required this.groups,
    required this.isGradesMode,
    required this.onPrimary,
    required this.onSecondary,
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
                      Text(subject,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(groupName, style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: groups.map((g) {
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
                                if (!isGradesMode) ...[
                                  const SizedBox(width: 10),
                                  const Icon(Icons.people_alt_outlined, size: 16),
                                  const SizedBox(width: 4),
                                  Text('${g.students.length}'),
                                ],
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
                    onPressed: () => onPrimary(main),
                    icon: Icon(isGradesMode ? Icons.star_border : Icons.fact_check),
                    label: Text(isGradesMode ? 'Capturar $groupName' : 'Tomar Lista $groupName'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onSecondary(main),
                    icon: Icon(isGradesMode ? Icons.history : Icons.history),
                    label: Text('Historial'),
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
