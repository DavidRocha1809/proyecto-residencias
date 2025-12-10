// lib/pages/grade_activity_grades_editor_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models.dart';

// Firestore directo para actualizar
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum EditSource { firestore, hive }

class GradeActivityGradesEditorPage extends StatefulWidget {
  final GroupClass groupClass;

  /// Identificador de la actividad (docId de Firestore o key de Hive)
  final String activityKey;

  /// Origen de la actividad
  final EditSource source;

  /// Valores iniciales
  final String initialTitle;
  final DateTime initialDate;
  final Map<String, dynamic> initialGrades;

  const GradeActivityGradesEditorPage({
    super.key,
    required this.groupClass,
    required this.activityKey,
    required this.source,
    required this.initialTitle,
    required this.initialDate,
    required this.initialGrades,
  });

  @override
  State<GradeActivityGradesEditorPage> createState() =>
      _GradeActivityGradesEditorPageState();
}

class _GradeActivityGradesEditorPageState
    extends State<GradeActivityGradesEditorPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleCtrl;
  late DateTime _date;

  bool _loading = true;
  List<Student> _students = [];
  final Map<String, TextEditingController> _gradeCtrls = {};

  String get _groupId => widget.groupClass.groupName.replaceAll('|', '_');
  String get _boxName => 'grades_log::$_groupId';

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle);
    _date = widget.initialDate;
    _load();
  }

  Future<void> _load() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('No autenticado');

    final snap = await FirebaseFirestore.instance
        .collection('teachers')
        .doc(uid)
        .collection('groups')
        .doc(_groupId)
        .collection('students')
        .get();

    final studs = snap.docs
        .map((d) => Student(id: d.id, name: d['name'] ?? ''))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    for (final s in studs) {
      _gradeCtrls[s.id] = TextEditingController(
        text: widget.initialGrades[s.id]?.toString() ?? '',
      );
    }

    setState(() {
      _students = studs;
      _loading = false;
    });
  } catch (e) {
    debugPrint('❌ Error cargando alumnos: $e');
    setState(() => _loading = false);
  }
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

    final title =
        _titleCtrl.text.trim().isEmpty ? 'Actividad' : _titleCtrl.text.trim();

    // Construir mapa de calificaciones actualizado
    final grades = <String, dynamic>{};
    for (final s in _students) {
      final txt = _gradeCtrls[s.id]!.text.trim();
      grades[s.id] = txt; // mantenemos string/num compatible
    }

    try {
      if (widget.source == EditSource.firestore) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) {
          throw 'Sesión inválida';
        }
        final ref = FirebaseFirestore.instance
            .collection('teachers')
            .doc(uid)
            .collection('grades')
            .doc(_groupId)
            .collection('activities')
            .doc(widget.activityKey);

        await ref.set({
          'activity': title,
          // guardamos date como string ISO corto para ser consistente con lo que ya usas
          'date': DateFormat('yyyy-MM-dd').format(_date),
          'grades': grades,
        }, SetOptions(merge: false));
      } else {
        // HIVE
        if (!Hive.isBoxOpen(_boxName)) await Hive.openBox(_boxName);
        final box = Hive.box(_boxName);
        final value = Map<String, dynamic>.from(
          (box.get(widget.activityKey) ?? const <String, dynamic>{})
              as Map<String, dynamic>,
        );

        await box.put(widget.activityKey, {
          ...value,
          'activity': title,
          'date': DateFormat('yyyy-MM-dd').format(_date),
          'grades': grades,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Actividad actualizada')));
      Navigator.pop(context, true); // <- indica que hubo cambios
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Editar calificaciones'),
        actions: [
          IconButton(
            tooltip: 'Guardar',
            icon: const Icon(Icons.save_outlined),
            onPressed: _save,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 56,
          child: FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_alt),
            label: const Text('Guardar cambios'),
          ),
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.star_border),
                        labelText: 'Título de la actividad',
                        border: UnderlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label: Text('Fecha: ${df.format(_date)}'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        shape: const StadiumBorder(),
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
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Matrícula: ${s.id}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
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
                                      decimal: true,
                                    ),
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
