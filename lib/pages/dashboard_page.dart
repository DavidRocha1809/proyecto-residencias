import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../local_groups.dart' as LG; // helpers + storage local
import 'attendance_page.dart';
import 'sessions_page.dart';
import 'students_editor_page.dart'; // editor de alumnos

class DashboardPage extends StatefulWidget {
  static const route = '/dashboard';
  final String teacherName;

  /// Mensaje opcional para advertir problema de autenticación (lo muestra al cargar)
  final String? authWarning;

  const DashboardPage({
    super.key,
    this.teacherName = 'Docente',
    this.authWarning,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String _query = '';
  List<GroupClass> _groups = [];

  @override
  void initState() {
    super.initState();
    _refreshGroups();

    // Si main.dart nos dejó una advertencia de auth, muéstrala una sola vez
    final warn = widget.authWarning;
    if (warn != null && warn.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(warn)));
      });
    }
  }

  Future<void> _refreshGroups() async {
    final items = await LG.LocalGroups.listGroups();
    if (!mounted) return;
    setState(() => _groups = items);
  }

  Future<void> _importGroupsAndStudentsFromCsv(BuildContext context) async {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('CSV vacío')));
        return;
      }

      // columnas requeridas
      final header = rows.first.map((e) => e.toString().trim()).toList();
      Map<String, int> col = {};
      for (final h in [
        'groupName',
        'subject',
        'start',
        'end',
        'turno',
        'dia',
        'matricula', // ó studentId
        'name',
      ]) {
        final i = header.indexOf(h);
        if (i < 0) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Falta columna "$h" en el CSV')),
          );
          return;
        }
        col[h] = i;
      }

      // Agrupar por (groupName, subject, turno, dia)
      final Map<String, Map<String, dynamic>> groups = {};
      for (var r = 1; r < rows.length; r++) {
        final row = rows[r];
        if (row.length < header.length) continue;

        final groupName = row[col['groupName']!]!.toString().trim();
        final subject = row[col['subject']!]!.toString().trim();
        final start = row[col['start']!]!.toString().trim();
        final end = row[col['end']!]!.toString().trim();
        final turno = row[col['turno']!]!.toString().trim();
        final dia = row[col['dia']!]!.toString().trim();
        final matricula = row[col['matricula']!]!.toString().trim();
        final name = row[col['name']!]!.toString().trim();

        if ([
          groupName,
          subject,
          turno,
          dia,
          matricula,
          name,
        ].any((s) => s.isEmpty)) {
          continue;
        }

        final key = '$groupName|$subject|$turno|$dia';
        groups.putIfAbsent(key, () {
          return {
            'groupName': groupName,
            'subject': subject,
            'turno': turno,
            'dia': dia,
            'start': start,
            'end': end,
            'students': <Map<String, dynamic>>[],
          };
        });

        (groups[key]!['students'] as List<Map<String, dynamic>>).add({
          'studentId': matricula,
          'name': name,
        });
      }

      final totalGroups = groups.length;
      final totalStudents = groups.values
          .map((g) => (g['students'] as List).length)
          .fold<int>(0, (a, b) => a + b);

      final ok =
          await showDialog<bool>(
            context: context,
            builder:
                (_) => AlertDialog(
                  title: const Text('Confirmar importación'),
                  content: Text(
                    'Se importarán $totalGroups grupo(s) y $totalStudents alumno(s) (local).',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Importar'),
                    ),
                  ],
                ),
          ) ??
          false;

      if (!ok) return;

      // Guardado local: 1) grupo  2) alumnos (con DEDUPE)
      for (final entry in groups.values) {
        final groupName = entry['groupName'] as String;
        final subject = entry['subject'] as String;
        final turno = entry['turno'] as String;
        final dia = entry['dia'] as String;
        final start = entry['start'] as String?;
        final end = entry['end'] as String?;
        final students =
            (entry['students'] as List).cast<Map<String, dynamic>>();

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

        // DEDUPE por studentId antes de guardar
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Importación local completa: $totalGroups grupo(s), $totalStudents alumno(s)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al importar: $e')));
    }
  }

  Future<void> _openEditorPicker() async {
    // Muestra un modal con la lista de grupos; al elegir uno, abre el editor
    final Map<String, List<GroupClass>> grouped = {};
    for (final g in _groups) {
      final key = '${g.subject} — ${g.groupName}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(g);
    }

    final keySelected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) {
        final keys = grouped.keys.toList()..sort();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemBuilder: (_, i) {
            final k = keys[i];
            final g = grouped[k]!.first; // usamos la primera variante
            return ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: Text(k),
              subtitle: Text('Turno ${g.turno ?? ''} · ${g.dia ?? ''}'),
              onTap: () => Navigator.pop(context, k),
            );
          },
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemCount: keys.length,
        );
      },
    );

    if (keySelected == null) return;

    // Encuentra el GroupClass base para ese key
    final parts = keySelected.split(' — ');
    if (parts.length < 2) return;
    final subject = parts[0];
    final groupName = parts[1];

    final chosen = _groups.firstWhere(
      (g) => g.subject == subject && g.groupName == groupName,
      orElse: () => _groups.first,
    );

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StudentsEditorPage(groupClass: chosen)),
    );
    // Al volver, refrescamos para que se vea el total actualizado
    await _refreshGroups();
  }

  @override
  Widget build(BuildContext context) {
    // Filtro por texto
    final filtered =
        _groups.where((g) {
          final q = _query.toLowerCase();
          return g.subject.toLowerCase().contains(q) ||
              g.groupName.toLowerCase().contains(q) ||
              (g.turno ?? '').toLowerCase().contains(q) ||
              (g.dia ?? '').toLowerCase().contains(q);
        }).toList();

    // Agrupar por (subject + groupName) para una tarjeta por grupo
    final Map<String, List<GroupClass>> grouped = {};
    for (final g in filtered) {
      final key = '${g.subject}|||${g.groupName}';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(g);
    }

    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: Image.asset(
            'assets/images/logo_cetis31.png',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
        ),
        leadingWidth: 56,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sistema CETIS 31',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              'Bienvenido, ${widget.teacherName}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Importar CSV',
            icon: const Icon(Icons.upload_file),
            onPressed: () => _importGroupsAndStudentsFromCsv(context),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilledButton.tonal(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              child: const Text('Salir'),
            ),
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
          Expanded(
            child:
                grouped.isEmpty
                    ? const Center(child: Text('Aún no hay grupos importados'))
                    : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      itemBuilder: (_, i) {
                        final key = grouped.keys.elementAt(i);
                        final list = grouped[key]!;
                        final subject = list.first.subject;
                        final groupName = list.first.groupName;
                        return _GroupMergedCard(
                          subject: subject,
                          groupName: groupName,
                          groups: list,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemCount: grouped.length,
                    ),
          ),
        ],
      ),
      // 🔻 Botón fijo abajo: Editar lista
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _openEditorPicker,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Editar lista'),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta combinada por (materia + grupo)
/// Muestra varias líneas (turno/día) pero **un solo par de botones**.
class _GroupMergedCard extends StatelessWidget {
  final String subject;
  final String groupName;
  final List<GroupClass> groups;
  const _GroupMergedCard({
    required this.subject,
    required this.groupName,
    required this.groups,
  });

  @override
  Widget build(BuildContext context) {
    // Usamos el primer registro del grupo para abrir Tomar Lista / Historial
    final GroupClass main = groups.first;

    // (opcional) suma total de alumnos si ya se carga en GroupClass
    final totalStudents = groups.fold<int>(
      0,
      (sum, g) => sum + g.students.length,
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0.6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Encabezado
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
                      // Lista de variantes (turno/día)
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
                                    const SizedBox(width: 10),
                                    const Icon(
                                      Icons.people_alt_outlined,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    Text('${g.students.length}'),
                                  ],
                                ),
                              );
                            }).toList(),
                      ),
                      if (totalStudents > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Total alumnos (suma de variantes): $totalStudents',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Un solo par de botones para TODO el grupo
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder:
                              (_) => AttendancePage(
                                groupClass: main,
                                initialDate: DateTime.now(),
                              ),
                        ),
                      );
                    },
                    child: Text('Tomar Lista $groupName'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SessionsPage(groupClass: main),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Historial'),
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
