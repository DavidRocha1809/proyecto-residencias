import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../local_groups.dart' as LG;
import '../models/grade_models.dart';

import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:flutter/services.dart' show rootBundle;

// Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Servicio (para eliminar)
import '../services/grades_service.dart';

// ✅ Importa el editor de calificaciones (nuevo)
import 'grade_activity_editor_page.dart';

class GradesHistoryPage extends StatefulWidget {
  final GroupClass groupClass;
  const GradesHistoryPage({super.key, required this.groupClass});

  @override
  State<GradesHistoryPage> createState() => _GradesHistoryPageState();
}

class _GradesHistoryPageState extends State<GradesHistoryPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  List<Student> _students = [];
  List<_Activity> _activities = [];
  bool _loading = true;

  String _studentQuery = '';

  String get _groupId => LG.groupKeyOf(widget.groupClass);
  String get _logBox => 'grades_log::$_groupId';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final studs = await LG.LocalGroups.listStudents(groupId: _groupId)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final cloud = await _loadFromFirestore();
      final list = cloud.isNotEmpty ? cloud : await _loadFromHive();

      if (!mounted) return;
      setState(() {
        _students = studs;
        _activities = list..sort((a, b) => a.date.compareTo(b.date));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el historial: $e')),
      );
    }
  }

  // ---------- Firestore ----------
  Future<List<_Activity>> _loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final col = FirebaseFirestore.instance
        .collection('teachers')
        .doc(uid)
        .collection('grades')
        .doc(_groupId)
        .collection('activities');

    final snap = await col.get();
    final out = <_Activity>[];

    for (final d in snap.docs) {
      final m = d.data();

      DateTime? date;
      final vdate = m['date'];
      if (vdate is Timestamp) {
        final t = vdate.toDate();
        date = DateTime(t.year, t.month, t.day);
      } else if (vdate is String) {
        try {
          final p = vdate.split('-').map((e) => int.parse(e)).toList();
          date = DateTime(p[0], p[1], p[2]);
        } catch (_) {}
      }
      if (date == null) continue;

      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      if (date.isBefore(from) || date.isAfter(to)) continue;

      out.add(_Activity(
        key: d.id,
        date: date,
        name: (m['activity'] ?? '').toString(),
        grades: Map<String, dynamic>.from(m['grades'] ?? const {}),
        source: _Source.firestore,
        raw: m,
      ));
    }
    return out;
  }

  // ---------- Hive ----------
  Future<List<_Activity>> _loadFromHive() async {
    if (!Hive.isBoxOpen(_logBox)) await Hive.openBox(_logBox);
    final box = Hive.box(_logBox);
    final List<_Activity> out = [];

    for (final k in box.keys) {
      final v = box.get(k);
      if (v is! Map) continue;

      DateTime? date;
      final rawDate = v['date'];
      if (rawDate is int) {
        final d = DateTime.fromMillisecondsSinceEpoch(rawDate);
        date = DateTime(d.year, d.month, d.day);
      } else if (rawDate is String && rawDate.isNotEmpty) {
        try {
          final p = rawDate.split('-').map((e) => int.parse(e)).toList();
          date = DateTime(p[0], p[1], p[2]);
        } catch (_) {}
      }
      if (date == null) continue;

      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      if (date.isBefore(from) || date.isAfter(to)) continue;

      out.add(_Activity(
        key: k.toString(),
        date: date,
        name: (v['activity'] ?? '').toString(),
        grades: Map<String, dynamic>.from(v['grades'] ?? const {}),
        source: _Source.hive,
        raw: v,
      ));
    }
    return out;
  }

  List<_Activity> _inRange() {
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return _activities
        .where((a) => !a.date.isBefore(from) && !a.date.isAfter(to))
        .toList();
  }

  Future<void> _pickFrom() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(_from.year - 1),
      lastDate: DateTime(_to.year + 1),
      locale: const Locale('es', 'MX'),
    );
    if (r != null) setState(() => _from = r);
    await _loadAll();
  }

  Future<void> _pickTo() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(_from.year - 1),
      lastDate: DateTime(_to.year + 1),
      locale: const Locale('es', 'MX'),
    );
    if (r != null) setState(() => _to = r);
    await _loadAll();
  }

  // --------- Exportación PDF (NO TOCADO) ----------
  Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/images/logo_cetis31.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  Future<void> _exportGeneralPdf() async {
    try {
      final logo = await _loadLogo();
      final totals = _computeTotals();
      final rows = <List<String>>[
        ['Matrícula', 'Nombre del alumno', 'Total de actividades', 'Total de entregas', 'Promedio'],
      ];
      for (final s in _students) {
        final t = totals[s.id] ?? const _Totals();
        final prom = (t.promedio == null) ? '-' : t.promedio!.toStringAsFixed(1);
        rows.add([s.id, s.name, '${t.totalActividades}', '${t.totalEntregas}', prom]);
      }

      final df = DateFormat('dd/MM/yyyy');
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(children: [
            pw.SizedBox(width: 48, height: 48, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Sistema CETIS 31', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Resumen de calificaciones', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('${widget.groupClass.subject}   ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Rango: ${df.format(_from)} a ${df.format(_to)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(data: rows),
          pw.SizedBox(height: 10),
          pw.Text('Activida rango: ${_inRange().length}', style: const pw.TextStyle(fontSize: 10)),
        ],
      ));

      await Printing.sharePdf(bytes: await doc.save(), filename: 'resumen_${widget.groupClass.groupName}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  Future<void> _exportActivityPdf(_Activity a) async {
    try {
      final logo = await _loadLogo();
      final rows = <List<String>>[
        ['Matrícula', 'Nombre del alumno', 'Calificación'],
      ];
      for (final s in _students) {
        final txt = a.grades[s.id]?.toString() ?? '';
        rows.add([s.id, s.name, txt]);
      }

      final df = DateFormat('dd/MM/yyyy');
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(children: [
            pw.SizedBox(width: 48, height: 48, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Sistema CETIS 31', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Actividad: ${a.name.isEmpty ? '(sin título)' : a.name}', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('${widget.groupClass.subject}   ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Fecha: ${df.format(a.date)}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(data: rows),
        ],
      ));

      await Printing.sharePdf(bytes: await doc.save(), filename: 'actividad_${DateFormat('yyyyMMdd').format(a.date)}.pdf');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF de la actividad: $e')));
    }
  }

  Future<void> _exportStudentPdf(Student s) async {
    try {
      final bytes = await rootBundle.load('assets/images/logo_cetis31.png');
      final logo = pw.MemoryImage(bytes.buffer.asUint8List());
      final inRange = _inRange();
      final df = DateFormat('dd/MM/yyyy');
      final rows = <List<String>>[
        ['Fecha', 'Actividad', 'Calificación'],
      ];

      int entregas = 0;
      double suma = 0;
      int cuenta = 0;

      for (final a in inRange) {
        final val = a.grades[s.id];
        final txt = (val == null) ? '' : val.toString();
        rows.add([df.format(a.date), a.name.isEmpty ? '(sin título)' : a.name, txt]);

        if (txt.trim().isNotEmpty) {
          final n = num.tryParse(txt);
          if (n != null) {
            suma += n.toDouble();
            cuenta++;
          }
          entregas++;
        }
      }

      final promedio = (cuenta == 0) ? '-' : (suma / cuenta).toStringAsFixed(1);

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => [
            pw.Row(children: [
              pw.SizedBox(width: 48, height: 48, child: pw.Image(logo)),
              pw.SizedBox(width: 12),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Sistema CETIS 31', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Historial de calificaciones por alumno', style: const pw.TextStyle(fontSize: 12)),
                ],
              ),
            ]),
            pw.SizedBox(height: 8),
            pw.Text('${widget.groupClass.subject}   ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
                style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Alumno: ${s.name}  •  Matrícula: ${s.id}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Rango: ${df.format(_from)} a ${df.format(_to)}', style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 10),
            pw.TableHelper.fromTextArray(data: rows),
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Entregas: $entregas   •   Promedio: $promedio', style: const pw.TextStyle(fontSize: 10)),
            ),
          ],
        ),
      );

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'calificaciones_${s.id}_${DateFormat('yyyyMMdd').format(_from)}_${DateFormat('yyyyMMdd').format(_to)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo generar el PDF del alumno: $e')));
    }
  }

  Map<String, _Totals> _computeTotals() {
    final inRange = _inRange();
    final totals = <String, _Totals>{};
    final totalActs = inRange.length;

    for (final s in _students) {
      int entregas = 0;
      double sum = 0;
      int count = 0;

      for (final a in inRange) {
        final v = a.grades[s.id];
        if (v == null) continue;
        final txt = v.toString().trim();
        if (txt.isEmpty) continue;
        final n = num.tryParse(txt);
        if (n == null) continue;

        entregas++;
        sum += n.toDouble();
        count++;
      }

      final avg = count == 0 ? null : (sum / count);
      totals[s.id] = _Totals(
        totalActividades: totalActs,
        totalEntregas: entregas,
        promedio: avg,
      );
    }
    return totals;
  }

  // ====== Eliminar ======
  Future<void> _deleteActivity(_Activity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar actividad'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      if (a.source == _Source.firestore) {
        await GradesService.deleteActivity(groupId: _groupId, activityId: a.key);
      } else {
        if (!Hive.isBoxOpen(_logBox)) await Hive.openBox(_logBox);
        final box = Hive.box(_logBox);
        await box.delete(a.key);
      }
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actividad eliminada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  // ✅ NUEVO: abrir editor de calificaciones
  Future<void> _openGradesEditor(_Activity a) async {
    final src = (a.source == _Source.firestore)
        ? EditSource.firestore
        : EditSource.hive;

    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => GradeActivityGradesEditorPage(
          groupClass: widget.groupClass,
          activityKey: a.key,
          source: src,
          initialTitle: a.name,
          initialDate: a.date,
          initialGrades: a.grades,
        ),
      ),
    );

    if (changed == true) {
      await _loadAll();
    }
  }

  // ====== UI ======
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final inRange = _inRange();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de calaciones'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _students.isEmpty ? null : _pickExport,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Exportar PDF'),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFrom,
                          icon: const Icon(Icons.event),
                          label: Text('Desde: ${df.format(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickTo,
                          icon: const Icon(Icons.event_available),
                          label: Text('Hasta: ${df.format(_to)}'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Actividades en rango: ${inRange.length}',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: inRange.isEmpty
                      ? const Center(child: Text('No hay actividades en el rango seleccionado'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: inRange.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final a = inRange[i];
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.pink.shade50,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.star_border, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          a.name.isEmpty ? 'Actividad ${i + 1}' : a.name,
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(DateFormat('dd/MM/yyyy').format(a.date)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar calificaciones',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _openGradesEditor(a),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteActivity(a),
                                      ),
                                      IconButton(
                                        tooltip: 'PDF actividad',
                                        icon: const Icon(Icons.picture_as_pdf_outlined),
                                        onPressed: () => _exportActivityPdf(a),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  // ====== selector de exportación (NO TOCADO) ======
  Future<void> _pickExport() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF general (resumen por alumno)'),
              onTap: () async {
                Navigator.pop(context);
                await _exportGeneralPdf();
              },
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('PDF de un alumno'),
              subtitle: const Text('Elige un alumno del grupo'),
              onTap: () {
                Navigator.pop(context);
                _chooseStudentAndExport();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseStudentAndExport() async {
    _studentQuery = '';
    final res = await showModalBottomSheet<Student>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSt) {
            final q = _studentQuery.toLowerCase();
            final list = _students
                .where((s) => s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q))
                .toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Elegir alumno', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        autofocus: true,
                        onChanged: (v) => setSt(() => _studentQuery = v),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Buscar por nombre o matrícula…',
                        ),
                      ),
                    ),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemBuilder: (_, i) {
                          final s = list[i];
                          return ListTile(
                            leading: const Icon(Icons.person_outline),
                            title: Text(s.name),
                            subtitle: Text('Matrícula: ${s.id}'),
                            onTap: () => Navigator.pop(ctx, s),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 0),
                        itemCount: list.length,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (res != null) {
      await _exportStudentPdf(res);
    }
  }
}

enum _Source { firestore, hive }

class _Activity {
  final String key;
  final DateTime date;
  final String name;
  final Map<String, dynamic> grades;
  final _Source source;
  final Object? raw;

  _Activity({
    required this.key,
    required this.date,
    required this.name,
    required this.grades,
    required this.source,
    this.raw,
  });
}

class _Totals {
  final int totalActividades;
  final int totalEntregas;
  final double? promedio;

  const _Totals({
    this.totalActividades = 0,
    this.totalEntregas = 0,
    this.promedio,
  });
}
