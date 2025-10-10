// lib/pages/grades_capture_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models.dart';
import '../local_groups.dart' as LG;
import '../services/grades_service.dart';

class GradesCapturePage extends StatefulWidget {
  final GroupClass groupClass;

  /// Opcional: si algún día pasas una actividad existente, se usará para prellenar.
  /// En el flujo actual NO se pasa, así que todo queda en blanco.
  final Map<String, dynamic>? existing; // {title, date(yyyy-MM-dd), grades: {id:score}}

  const GradesCapturePage({
    super.key,
    required this.groupClass,
    this.existing,
  });

  @override
  State<GradesCapturePage> createState() => _GradesCapturePageState();
}

class _GradesCapturePageState extends State<GradesCapturePage> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  DateTime _date = DateTime.now();

  /// Un controlador por alumno
  final Map<String, TextEditingController> _gradeCtrls = {};

  bool _loading = true;
  List<Student> _students = [];

  String get _groupId => LG.groupKeyOf(widget.groupClass);
  String get _boxName => 'grades_log::$_groupId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // 1) alumnos reales del grupo
    final studs = await LG.LocalGroups.listStudents(groupId: _groupId)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    // 2) SI y solo SI nos pasan existing (modo edición), prellenamos;
    //    de lo contrario, SIEMPRE en blanco (lo que pediste).
    if (widget.existing != null) {
      final ex = widget.existing!;
      _titleCtrl.text = (ex['title'] ?? '').toString();
      final raw = (ex['date'] ?? '').toString();
      try {
        final p = raw.split('-').map((e) => int.parse(e)).toList();
        _date = DateTime(p[0], p[1], p[2]);
      } catch (_) {
        _date = DateTime.now();
      }
      final grades = Map<String, dynamic>.from(ex['grades'] ?? const {});
      for (final s in studs) {
        _gradeCtrls[s.id] = TextEditingController(
          text: grades[s.id]?.toString() ?? '',
        );
      }
    } else {
      // >>>> SIEMPRE BLANCO <<<<
      _titleCtrl.clear();
      _date = DateTime.now();
      for (final s in studs) {
        _gradeCtrls[s.id] = TextEditingController(text: '');
      }
    }

    setState(() {
      _students = studs;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _gradeCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
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
    if (!_formKey.currentState!.validate()) return;

    final title = _titleCtrl.text.trim().isEmpty
        ? 'Actividad'
        : _titleCtrl.text.trim();

    // Construimos el mapa de calificaciones por matrícula
    final grades = <String, dynamic>{};
    for (final s in _students) {
      final txt = _gradeCtrls[s.id]!.text.trim();
      grades[s.id] = txt.isEmpty ? '' : txt; // guardamos tal cual (compatible)
    }

    try {
      // 1) Guardado local (Hive) para tu historial previo/compatibilidad
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox(_boxName);
      }
      final box = Hive.box(_boxName);
      final key = '${DateTime.now().millisecondsSinceEpoch}::$title';
      await box.put(key, {
        'activity': title,
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'grades': grades,
      });

      // 2) Guardado en Firestore (nuevo)
      await GradesService.saveActivity(
        groupId: _groupId,
        dateOnly: DateTime(_date.year, _date.month, _date.day),
        activityName: title,
        gradesByStudentId: grades,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Actividad guardada')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final g = widget.groupClass;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capturar calificaciones'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save_outlined),
            onPressed: _save,
          )
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_alt),
            label: const Text('Guardar actividad'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  // Nombre de la actividad
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.star_border),
                      labelText: 'Nombre de la actividad',
                      border: UnderlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Fecha
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event),
                    label: Text('Fecha: ${df.format(_date)}'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      shape: StadiumBorder(
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Lista de alumnos
                  ..._students.map((s) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.pink.shade50,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text('Matrícula: ${s.id}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: _gradeCtrls[s.id],
                              textAlign: TextAlign.right,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                hintText: '',
                                border: UnderlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
    );
  }
}
