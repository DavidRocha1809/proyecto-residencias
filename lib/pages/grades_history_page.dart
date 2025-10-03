

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../local_groups.dart' as LG;

import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:flutter/services.dart' show rootBundle;

import 'grades_capture_page.dart';

class GradesHistoryPage extends StatefulWidget {
  final GroupClass groupClass;
  const GradesHistoryPage({super.key, required this.groupClass});

  @override
  State<GradesHistoryPage> createState() => _GradesHistoryPageState();
}

class _GradesHistoryPageState extends State<GradesHistoryPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to   = DateTime.now();

  List<Student> _students = [];
  List<_Activity> _activities = [];
  bool _loading = true;

  // ------- NUEVO: búsqueda para elegir alumno en exportación
  String _studentQuery = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _logBoxName() async {
    final gid = LG.groupKeyOf(widget.groupClass);
    return 'grades_log::$gid';
  }

  Future<void> _load() async {
    try {
      final gid = LG.groupKeyOf(widget.groupClass);
      final studs = await LG.LocalGroups.listStudents(groupId: gid)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final boxName = await _logBoxName();
      if (!Hive.isBoxOpen(boxName)) await Hive.openBox(boxName);
      final box = Hive.box(boxName);

      final List<_Activity> acts = [];
      for (final k in box.keys) {
        final map = box.get(k);
        if (map is Map) {
          final dt = DateTime.fromMillisecondsSinceEpoch(map['date'] as int);
          acts.add(_Activity(
            key: k.toString(),
            date: DateTime(dt.year, dt.month, dt.day),
            name: (map['activity'] ?? '').toString(),
            grades: Map<String, dynamic>.from(map['grades'] ?? const {}),
          ));
        }
      }
      acts.sort((a, b) => a.date.compareTo(b.date));

      if (!mounted) return;
      setState(() {
        _students = studs;
        _activities = acts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar historial: $e')),
      );
    }
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
  }

  List<_Activity> _inRangeActivities() {
    final from = DateTime(_from.year, _from.month, _from.day);
    final to   = DateTime(_to.year,   _to.month,   _to.day);
    return _activities.where((a) =>
      !a.date.isBefore(from) && !a.date.isAfter(to)
    ).toList();
  }

  Map<String, _Totals> _computeTotals() {
    final inRange = _inRangeActivities();
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

  // ===== Exportaciones =====
  Future<pw.MemoryImage> _loadLogo() async {
    final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
    return pw.MemoryImage(logoBytes.buffer.asUint8List());
  }

  Future<void> _exportGeneralPdf() async {
    try {
      final df = DateFormat('dd/MM/yyyy');
      final totals = _computeTotals();
      final logoImage = await _loadLogo();

      final rows = <List<String>>[
        ['Matrícula','Nombre del alumno','Total de actividades','Total de entregas','Promedio'],
      ];
      for (final s in _students) {
        final t = totals[s.id] ?? const _Totals();
        final prom = (t.promedio == null) ? '-' : t.promedio!.toStringAsFixed(1);
        rows.add([s.id, s.name, '${t.totalActividades}', '${t.totalEntregas}', prom]);
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
              pw.Text('Resumen de calificaciones', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('${widget.groupClass.subject}   ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Rango: ${df.format(_from)} a ${df.format(_to)}',
              style: const pw.TextStyle(fontSize: 10)),
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
          pw.SizedBox(height: 10),
          pw.Text('Actividades encontradas: ${_inRangeActivities().length}',
              style: const pw.TextStyle(fontSize: 10)),
        ],
      ));

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'resumen_${widget.groupClass.groupName}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF: $e')),
      );
    }
  }

  // ===== NUEVO: Exportar PDF de un solo alumno en el rango =====
  Future<void> _exportStudentPdf(Student s) async {
    try {
      final df = DateFormat('dd/MM/yyyy');
      final logoImage = await _loadLogo();
      final inRange = _inRangeActivities();

      final rows = <List<String>>[
        ['Fecha','Actividad','Calificación'],
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
              pw.SizedBox(width: 48, height: 48, child: pw.Image(logoImage)),
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
            pw.Text('${widget.groupClass.subject}   ${widget.groupClass.groupName}',
                style: const pw.TextStyle(fontSize: 11)),
            pw.Text('Alumno: ${s.name}    Matrícula: ${s.id}', style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Rango: ${df.format(_from)} a ${df.format(_to)}', style: const pw.TextStyle(fontSize: 10)),
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
            pw.SizedBox(height: 10),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Entregas: $entregas      Promedio: $promedio', style: const pw.TextStyle(fontSize: 10)),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF del alumno: $e')),
      );
    }
  }

  // ===== NUEVO: selector de tipo de exportación =====
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

  // ===== NUEVO: buscador/lista para elegir alumno y exportar =====
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
            final list = _students.where((s) =>
              s.name.toLowerCase().contains(q) || s.id.toLowerCase().contains(q)
            ).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
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

  Future<void> _exportActivityPdf(_Activity a) async {
    try {
      final df = DateFormat('dd/MM/yyyy');
      final logoImage = await _loadLogo();

      final rows = <List<String>>[
        ['Matrícula','Nombre del alumno','Calificación'],
      ];
      for (final s in _students) {
        final txt = a.grades[s.id]?.toString() ?? '';
        rows.add([s.id, s.name, txt]);
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
              pw.Text('Actividad: ${a.name.isEmpty ? '(sin título)' : a.name}', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('${widget.groupClass.subject}   ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Fecha: ${df.format(a.date)}', style: const pw.TextStyle(fontSize: 10)),
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

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'actividad_${DateFormat('yyyyMMdd').format(a.date)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo generar el PDF de la actividad: $e')),
      );
    }
  }

  // ===== Editar / Eliminar / Editar calificaciones =====

  Future<void> _editActivityMeta(_Activity a) async {
    final df = DateFormat('dd/MM/yyyy');
    final nameCtl = TextEditingController(text: a.name);
    DateTime date = a.date;

    final res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar actividad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(
                labelText: 'Nombre',
                prefixIcon: Icon(Icons.star_border),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Fecha: ${df.format(date)}')),
                TextButton.icon(
                  onPressed: () async {
                    final r = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(date.year - 1),
                      lastDate: DateTime(date.year + 1),
                      locale: const Locale('es', 'MX'),
                    );
                    if (r != null) {
                      date = DateTime(r.year, r.month, r.day);
                      (context as Element).markNeedsBuild();
                    }
                  },
                  icon: const Icon(Icons.event),
                  label: const Text('Cambiar'),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );

    if (res != true) return;

    try {
      final boxName = await _logBoxName();
      final box = Hive.box(boxName);

      final value = Map<String, dynamic>.from(box.get(a.key) as Map);
      final newKey = '${date.millisecondsSinceEpoch}::${nameCtl.text.trim()}';

      await box.put(newKey, {
        'activity': nameCtl.text.trim(),
        'date': DateTime(date.year, date.month, date.day).millisecondsSinceEpoch,
        'grades': Map<String, dynamic>.from(value['grades'] ?? const {}),
      });
      await box.delete(a.key);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actividad actualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo editar: $e')),
      );
    }
  }

  Future<void> _editActivityGrades(_Activity a) async {
    // Abre la captura en modo edición con la clave de actividad existente
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GradesCapturePage(
          groupClass: widget.groupClass,
          editingActivityKey: a.key,
        ),
      ),
    );
    // Al volver, recargamos para ver cambios
    await _load();
  }

  Future<void> _deleteActivity(_Activity a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar actividad'),
        content: Text(
            '¿Seguro que quieres eliminar "${a.name.isEmpty ? '(sin título)' : a.name}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final boxName = await _logBoxName();
      final box = Hive.box(boxName);
      await box.delete(a.key);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actividad eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final inRange = _inRangeActivities();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de calificaciones'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            // ======= NUEVO: ahora abre el selector de exportación =======
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
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                leading: const Icon(Icons.star_border),
                                title: Text(a.name.isEmpty ? 'Actividad ${i+1}' : a.name),
                                subtitle: Text(df.format(a.date)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Editar nombre y fecha',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editActivityMeta(a),
                                    ),
                                    IconButton(
                                      tooltip: 'Editar calificaciones',
                                      icon: const Icon(Icons.fact_check_outlined),
                                      onPressed: () => _editActivityGrades(a),
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _deleteActivity(a),
                                    ),
                                    // Exportar PDF de esta actividad (ya existía)
                                    IconButton(
                                      tooltip: 'Exportar PDF de actividad',
                                      icon: const Icon(Icons.picture_as_pdf_outlined),
                                      onPressed: () => _exportActivityPdf(a),
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
    );
  }
}

class _Activity {
  final String key;
  final DateTime date;
  final String name;
  final Map<String, dynamic> grades;
  _Activity({
    required this.key,
    required this.date,
    required this.name,
    required this.grades,
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
