// lib/pages/grades_capture_page.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models.dart';
import '../local_groups.dart' as LG;

class GradesCapturePage extends StatefulWidget {
  const GradesCapturePage({super.key});

  @override
  State<GradesCapturePage> createState() => _GradesCapturePageState();
}

class _GradesCapturePageState extends State<GradesCapturePage> {
  final _formKey = GlobalKey<FormState>();
  List<GroupClass> _groups = [];
  GroupClass? _selected;
  bool _loading = true;

  // mapa en memoria: studentId -> TextEditingController
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final g = await LG.LocalGroups.listGroups();
    if (!mounted) return;
    setState(() {
      _groups = g;
      _selected = g.isEmpty ? null : g.first;
      _loading = false;
    });
    if (_selected != null) {
      await _loadStudentsAndExistingGrades();
    }
  }

  Future<Box> _ensureGradesBox(String groupId) async {
    final name = 'grades::$groupId';
    if (!Hive.isBoxOpen(name)) {
      await Hive.openBox(name);
    }
    return Hive.box(name);
  }

  Future<void> _loadStudentsAndExistingGrades() async {
    if (_selected == null) return;
    setState(() => _loading = true);

    final groupId = LG.groupKeyOf(_selected!);
    final students = await LG.LocalGroups.listStudents(groupId: groupId);
    final box = await _ensureGradesBox(groupId);

    // Limpia y vuelve a crear controllers
    for (final c in _controllers.values) c.dispose();
    _controllers.clear();

    for (final s in students) {
      final existing = box.get(s.id); // puede ser num o String
      final initial = (existing == null) ? '' : existing.toString();
      _controllers[s.id] = TextEditingController(text: initial);
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_selected == null) return;
    if (!_formKey.currentState!.validate()) return;

    final groupId = LG.groupKeyOf(_selected!);
    final box = await _ensureGradesBox(groupId);

    for (final entry in _controllers.entries) {
      final raw = entry.value.text.trim();
      if (raw.isEmpty) {
        await box.delete(entry.key); // borra si quedó vacío
        continue;
      }
      final val = num.tryParse(raw);
      if (val == null) continue;
      await box.put(entry.key, val);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calificaciones guardadas ✅')),
    );
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturar calificaciones'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save_outlined),
            onPressed: _save,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('No hay grupos cargados'))
              : Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Selector de grupo
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: Row(
                          children: [
                            const Text('Grupo:'),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<GroupClass>(
                                value: _selected,
                                items: _groups.map((g) {
                                  final label =
                                      '${g.subject} — ${g.groupName} (${g.turno ?? ''} ${g.dia ?? ''})';
                                  return DropdownMenuItem(
                                    value: g,
                                    child: Text(label),
                                  );
                                }).toList(),
                                onChanged: (g) async {
                                  setState(() => _selected = g);
                                  await _loadStudentsAndExistingGrades();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Lista de alumnos con campo de calificación
                      Expanded(
                        child: FutureBuilder<List<Student>>(
                          future: _selected == null
                              ? Future.value(const [])
                              : LG.LocalGroups.listStudents(
                                  groupId: LG.groupKeyOf(_selected!),
                                ),
                          builder: (context, snap) {
                            if (!snap.hasData) {
                              return const SizedBox();
                            }
                            final students = snap.data!;
                            if (students.isEmpty) {
                              return const Center(
                                child: Text('Este grupo no tiene alumnos'),
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                              itemCount: students.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final s = students[i];
                                final ctl =
                                    _controllers[s.id] ??= TextEditingController();
                                return Card(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          flex: 5,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(s.name,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium),
                                              const SizedBox(height: 4),
                                              Text('ID: ${s.id}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 2,
                                          child: TextFormField(
                                            controller: ctl,
                                            textAlign: TextAlign.center,
                                            keyboardType:
                                                const TextInputType.numberWithOptions(
                                                    decimal: true),
                                            decoration: const InputDecoration(
                                              labelText: 'Calif.',
                                              hintText: '0–100',
                                            ),
                                            validator: (v) {
                                              final t = (v ?? '').trim();
                                              if (t.isEmpty) return null;
                                              final n = num.tryParse(t);
                                              if (n == null) {
                                                return 'Número';
                                              }
                                              if (n < 0 || n > 100) {
                                                return '0–100';
                                              }
                                              return null;
                                            },
                                          ),
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
                ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar calificaciones'),
          ),
        ),
      ),
    );
  }
}
