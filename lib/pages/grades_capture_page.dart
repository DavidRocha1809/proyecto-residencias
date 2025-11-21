import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

import '../models/grade_models.dart';
import '../models.dart';
import '../services/grades_service.dart';

class GradesCapturePage extends StatefulWidget {
  final GroupClass groupClass;
  final Map<String, dynamic>? existing;

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

  final Map<String, TextEditingController> _gradeCtrls = {};
  bool _loading = true;
  List<Student> _students = [];

  String? _activityId;

  @override
  void initState() {
    super.initState();
    _loadStudentsFromAssignedGroup();
  }

  Future<void> _loadStudentsFromAssignedGroup() async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('No hay usuario autenticado.');

      final groupId = widget.groupClass.id;
      final docSnap = await FirebaseFirestore.instance
          .collection('teachers')
          .doc(uid)
          .collection('assigned_groups')
          .doc(groupId)
          .get();

      if (!docSnap.exists) throw Exception('El grupo no existe.');

      final data = docSnap.data()!;
      final studentsData = data['students'] ?? [];

      final studs = List<Map<String, dynamic>>.from(studentsData)
          .map((s) => Student(
                id: s['matricula'] ?? '',
                name: s['name'] ?? '',
              ))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final ex = widget.existing;
      if (ex != null) {
        _activityId = ex['id'];
        _titleCtrl.text = ex['activity'] ?? '';
        try {
          final raw = (ex['date'] ?? '').toString();
          final p = raw.split('-').map(int.parse).toList();
          _date = DateTime(p[0], p[1], p[2]);
        } catch (_) {}
        final grades = Map<String, dynamic>.from(ex['grades'] ?? {});
        for (final s in studs) {
          _gradeCtrls[s.id] =
              TextEditingController(text: grades[s.id]?.toString() ?? '');
        }
      } else {
        for (final s in studs) {
          _gradeCtrls[s.id] = TextEditingController();
        }
      }

      setState(() {
        _students = studs;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Error cargando alumnos desde assigned_groups: $e');
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando alumnos: $e')),
      );
    }
  }

  Future<void> _save() async {
  if (!_formKey.currentState!.validate()) return;

  final title =
      _titleCtrl.text.trim().isEmpty ? 'Actividad' : _titleCtrl.text.trim();

  final grades = <String, dynamic>{};
  for (final s in _students) {
    final txt = _gradeCtrls[s.id]!.text.trim();
    grades[s.id] = txt.isEmpty ? 0.0 : double.tryParse(txt) ?? 0.0;
  }

  try {
    if (_activityId == null) {
      _activityId = await GradesService.instance.createActivity(
        groupId: widget.groupClass.id,
        title: title,
        date: _date,
        records: grades.entries.map((e) {
          final student = _students.firstWhere(
            (s) => s.id == e.key,
            orElse: () => Student(id: e.key, name: 'Sin nombre'),
          );
          return GradeRecord(
            studentId: e.key,
            studentName: student.name,
            score: e.value as double, // 🔹 ahora siempre es double
          );
        }).toList(),
      );
    } else {
      await GradesService.instance.updateActivity(
        groupId: widget.groupClass.id,
        activityId: _activityId!,
        title: title,
        date: _date,
        records: grades.entries.map((e) {
          final student = _students.firstWhere(
            (s) => s.id == e.key,
            orElse: () => Student(id: e.key, name: 'Sin nombre'),
          );
          return GradeRecord(
            studentId: e.key,
            studentName: student.name,
            score: e.value as double, // 🔹 igual aquí
          );
        }).toList(),
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Actividad guardada')),
    );
    Navigator.pop(context, true);
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error al guardar: $e')),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? 'Capturar calificaciones'
            : 'Editar calificaciones'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const Center(
                  child: Text('No hay alumnos registrados en este grupo.'),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                    children: [
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.assignment_outlined),
                          labelText: 'Nombre de la actividad',
                        ),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(_date.year - 1),
                            lastDate: DateTime(_date.year + 1),
                            locale: const Locale('es', 'MX'),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                        icon: const Icon(Icons.event),
                        label: Text('Fecha: ${df.format(_date)}'),
                      ),
                      const SizedBox(height: 12),
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
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
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
                                    _GradeRangeFormatter(),
                                  ],
                                  decoration: const InputDecoration(
                                    hintText: '0 - 100',
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
      // 🔹 Nuevo botón inferior como en pase de lista
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFD32F2F),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text(
              'Guardar actividad',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}

// 🔹 Validador personalizado para rango 0–100 con decimales
class _GradeRangeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final doubleValue = double.tryParse(newValue.text);
    if (doubleValue == null) return oldValue;
    if (doubleValue < 0 || doubleValue > 100) return oldValue;

    return newValue;
  }
}
