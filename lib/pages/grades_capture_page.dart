import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../local_groups.dart' as LG;

class GradesCapturePage extends StatefulWidget {
  final GroupClass groupClass;

  /// Si no es null -> se edita una actividad ya existente (clave en grades_log::<gid>)
  final String? editingActivityKey;

  const GradesCapturePage({
    super.key,
    required this.groupClass,
    this.editingActivityKey,
  });

  @override
  State<GradesCapturePage> createState() => _GradesCapturePageState();
}

class _GradesCapturePageState extends State<GradesCapturePage> {
  final _nameCtl = TextEditingController();
  DateTime _date = DateTime.now(); // solo se usa en nuevo registro
  bool _loading = true;

  List<Student> _students = [];
  final Map<String, TextEditingController> _gradeCtl = {};

  bool get _isEdit => widget.editingActivityKey != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final gid = LG.groupKeyOf(widget.groupClass);
      final studs = await LG.LocalGroups.listStudents(groupId: gid)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // prepara controles
      for (final s in studs) {
        _gradeCtl[s.id] = TextEditingController();
      }

      // Si es edición, cargar actividad existente
      if (_isEdit) {
        final logBoxName = 'grades_log::$gid';
        if (!Hive.isBoxOpen(logBoxName)) await Hive.openBox(logBoxName);
        final logBox = Hive.box(logBoxName);
        final map = Map<String, dynamic>.from(logBox.get(widget.editingActivityKey) as Map);

        _nameCtl.text = (map['activity'] ?? '').toString();
        final dt = DateTime.fromMillisecondsSinceEpoch(map['date'] as int);
        _date = DateTime(dt.year, dt.month, dt.day);

        final grades = Map<String, dynamic>.from(map['grades'] ?? const {});
        for (final s in studs) {
          final v = grades[s.id];
          _gradeCtl[s.id]?.text = (v == null) ? '' : v.toString();
        }
      } else {
        // Modo nuevo: precargar último valor por alumno (opcional)
        final boxName = 'grades::$gid';
        if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
        final box = Hive.box(boxName);
        for (final s in studs) {
          final last = box.get(s.id);
          if (last != null) _gradeCtl[s.id]?.text = last.toString();
        }
      }

      if (!mounted) return;
      setState(() {
        _students = studs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar alumnos: $e')),
      );
    }
  }

  Future<void> _pickDate() async {
    if (_isEdit) return; // en edición no se cambia fecha desde aquí
    final r = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 1),
      locale: const Locale('es', 'MX'),
    );
    if (r != null) setState(() => _date = r);
  }

  Future<void> _save() async {
    try {
      final gid = LG.groupKeyOf(widget.groupClass);

      // quick box de último valor por alumno
      final quickBoxName = 'grades::$gid';
      if (!Hive.isBoxOpen(quickBoxName)) await Hive.openBox(quickBoxName);
      final quick = Hive.box(quickBoxName);

      // mapa de calificaciones
      final Map<String, dynamic> grades = {};
      for (final s in _students) {
        final t = _gradeCtl[s.id]?.text.trim() ?? '';
        if (t.isEmpty) {
          grades[s.id] = null;
        } else {
          final n = num.tryParse(t);
          grades[s.id] = n ?? t; // permite num o texto
          // actualiza último valor
          quick.put(s.id, grades[s.id]);
        }
      }

      // log de actividades
      final logBoxName = 'grades_log::$gid';
      if (!Hive.isBoxOpen(logBoxName)) await Hive.openBox(logBoxName);
      final logBox = Hive.box(logBoxName);

      if (_isEdit) {
        // sobrescribe solo el mapa de grades para la misma clave
        final prev = Map<String, dynamic>.from(logBox.get(widget.editingActivityKey) as Map);
        await logBox.put(widget.editingActivityKey, {
          'activity': prev['activity'],
          'date': prev['date'],
          'grades': grades,
        });
      } else {
        final key = '${DateTime(_date.year, _date.month, _date.day).millisecondsSinceEpoch}::${_nameCtl.text.trim()}';
        await logBox.put(key, {
          'activity': _nameCtl.text.trim(),
          'date': DateTime(_date.year, _date.month, _date.day).millisecondsSinceEpoch,
          'grades': grades,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_isEdit ? 'Calificaciones actualizadas' : 'Actividad guardada')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d/M/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar calificaciones' : 'Capturar calificaciones'),
        actions: [
          IconButton(
            onPressed: _students.isEmpty ? null : _save,
            icon: const Icon(Icons.save),
            tooltip: 'Guardar',
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _students.isEmpty ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(_isEdit ? 'Guardar cambios' : 'Guardar actividad'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: TextField(
                    controller: _nameCtl,
                    enabled: !_isEdit, // en edición el nombre lo cambias desde historial
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la actividad',
                      prefixIcon: Icon(Icons.star_border),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isEdit ? null : _pickDate,
                          icon: const Icon(Icons.event),
                          label: Text('Fecha: ${df.format(_date)}'),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _students.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final s = _students[i];
                      final ctl = _gradeCtl[s.id]!;
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: ListTile(
                          title: Text(s.name),
                          subtitle: Text('Matrícula: ${s.id}'),
                          trailing: SizedBox(
                            width: 90,
                            child: TextField(
                              controller: ctl,
                              textAlign: TextAlign.center,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: false),
                              decoration: const InputDecoration(
                                isDense: true,
                                hintText: '—',
                              ),
                            ),
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
