import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../local_groups.dart' as LG;

class StudentsEditorPage extends StatefulWidget {
  final GroupClass groupClass;
  const StudentsEditorPage({super.key, required this.groupClass});

  @override
  State<StudentsEditorPage> createState() => _StudentsEditorPageState();
}

class _StudentsEditorPageState extends State<StudentsEditorPage> {
  bool _loading = true;
  List<_EditableStudent> _rows = [];

  String get _groupId => LG.groupKeyFromParts(
    widget.groupClass.groupName,
    widget.groupClass.turno,
    widget.groupClass.dia,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // 👇 CAMBIO: listStudents en lugar de getStudents
    final students = await LG.LocalGroups.listStudents(groupId: _groupId);

    // Asegura dedupe y orden
    final seen = <String>{};
    final clean =
        students.where((s) => seen.add(s.id)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));

    _rows = clean.map((s) => _EditableStudent(id: s.id, name: s.name)).toList();

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    // Normaliza + dedupe
    final byId = <String, Map<String, dynamic>>{};
    for (final r in _rows) {
      final id = r.id.trim();
      if (id.isEmpty) continue;
      byId[id] = {'studentId': id, 'name': r.name.trim()};
    }

    await LG.LocalGroups.upsertStudentsBulk(
      groupId: _groupId,
      students: byId.values.toList(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Lista guardada ✅')));
    Navigator.pop(context); // volver al dashboard
  }

  Future<void> _importCsvReplace() async {
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

      final header = rows.first.map((e) => e.toString().trim()).toList();
      final nameIdx = header.indexOf('name');
      final idIdx =
          header.indexOf('matricula') >= 0
              ? header.indexOf('matricula')
              : header.indexOf('studentId');

      if (nameIdx < 0 || idIdx < 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El CSV debe tener columnas "matricula" (o "studentId") y "name"',
            ),
          ),
        );
        return;
      }

      final List<_EditableStudent> found = [];
      final seen = <String>{};

      for (var r = 1; r < rows.length; r++) {
        if (rows[r].length <= nameIdx || rows[r].length <= idIdx) continue;
        final id = rows[r][idIdx].toString().trim();
        final name = rows[r][nameIdx].toString().trim();
        if (id.isEmpty || name.isEmpty) continue;
        if (seen.add(id)) {
          found.add(_EditableStudent(id: id, name: name));
        }
      }

      if (found.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El CSV no contenía alumnos válidos')),
        );
        return;
      }

      final ok =
          await showDialog<bool>(
            context: context,
            builder:
                (_) => AlertDialog(
                  title: const Text('Reemplazar lista'),
                  content: Text(
                    'Se reemplazarán ${found.length} alumnos para este grupo. ¿Continuar?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reemplazar'),
                    ),
                  ],
                ),
          ) ??
          false;
      if (!ok) return;

      setState(() => _rows = found);
      await _save();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo importar: $e')));
    }
  }

  void _addEmpty() {
    setState(() => _rows.add(_EditableStudent(id: '', name: '')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(
          'Editar lista — ${widget.groupClass.subject} • ${widget.groupClass.groupName}',
        ),
        actions: [
          IconButton(
            tooltip: 'Importar CSV (reemplazar)',
            icon: const Icon(Icons.upload_file),
            onPressed: _importCsvReplace,
          ),
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save_outlined),
            onPressed: _save,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Alumnos: ${_rows.length}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _addEmpty,
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Agregar'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r = _rows[i];
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    initialValue: r.id,
                                    decoration: const InputDecoration(
                                      labelText: 'Matrícula / ID',
                                    ),
                                    onChanged: (v) => r.id = v,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 4,
                                  child: TextFormField(
                                    initialValue: r.name,
                                    decoration: const InputDecoration(
                                      labelText: 'Nombre',
                                    ),
                                    onChanged: (v) => r.name = v,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: 'Eliminar',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () {
                                    setState(() => _rows.removeAt(i));
                                  },
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
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar cambios'),
          ),
        ),
      ),
    );
  }
}

class _EditableStudent {
  String id;
  String name;
  _EditableStudent({required this.id, required this.name});
}
