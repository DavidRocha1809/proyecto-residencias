// lib/pages/attendance_history_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../models.dart';
import '../local_groups.dart' as LG;

// 🔥 Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final GroupClass groupClass;
  const AttendanceHistoryPage({super.key, required this.groupClass});

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  List<Student> _students = [];
  List<_Session> _sessions = [];
  bool _loading = true;

  String _studentQuery = '';

  String get _gid => LG.groupKeyOf(widget.groupClass);
  String get _boxName => 'attendance::$_gid';

  @override
  void initState() {
    super.initState();
    _load();
  }

  // =================== CARGA ===================
  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // 1) alumnos del grupo
      final studs = await LG.LocalGroups.listStudents(groupId: _gid)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      // 2) nube primero
      final cloud = await _loadFromFirestore();

      // 3) si nube vacío, caer a local hive
      final local = cloud.isNotEmpty ? cloud : await _loadFromHive();

      if (!mounted) return;
      setState(() {
        _students = studs;
        _sessions = local..sort((a, b) => a.date.compareTo(b.date));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar asistencias: $e')),
      );
    }
  }

  /// Lee sesiones de Firestore en: teachers/{uid}/attendance/{groupId}/sessions
  Future<List<_Session>> _loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final col = FirebaseFirestore.instance
        .collection('teachers')
        .doc(uid)
        .collection('attendance')
        .doc(_gid)
        .collection('sessions');

    final snap = await col.get();

    final df = DateFormat('yyyy-MM-dd');
    final List<_Session> out = [];

    for (final d in snap.docs) {
      final map = d.data();

      // Fecha desde 'date' (Timestamp o String) o, en su defecto, desde id 'YYYY-MM-DD'
      DateTime? date;
      final vdate = map['date'];
      if (vdate is Timestamp) {
        final t = vdate.toDate();
        date = DateTime(t.year, t.month, t.day);
      } else if (vdate is String) {
        try {
          final parts = vdate.split('-').map((e) => int.parse(e)).toList();
          date = DateTime(parts[0], parts[1], parts[2]);
        } catch (_) {}
      }
      date ??= _tryParseDocIdDate(d.id, df);
      if (date == null) continue;

      // Rango
      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      if (date.isBefore(from) || date.isAfter(to)) continue;

      // Records
      final list = <_Mark>[];
      final recs = (map['records'] ?? []) as List<dynamic>;
      for (final r in recs) {
        if (r is Map) {
          final id = (r['studentId'] ?? r['id'] ?? '').toString();
          final status = (r['status'] ?? '').toString();
          if (id.isNotEmpty) list.add(_Mark(id: id, status: status));
        }
      }

      out.add(_Session(
        key: d.id,
        date: date,
        title: (map['title'] ?? '').toString(),
        records: list,
        source: _Source.firestore,
      ));
    }
    return out;
  }

  DateTime? _tryParseDocIdDate(String id, DateFormat df) {
    try {
      return df.parseStrict(id);
    } catch (_) {
      return null;
    }
  }

  /// Carga desde Hive
  Future<List<_Session>> _loadFromHive() async {
    if (!Hive.isBoxOpen(_boxName)) {
      await Hive.openBox(_boxName);
    }
    final box = Hive.box(_boxName);

    final List<_Session> list = [];
    for (final k in box.keys) {
      final v = box.get(k);
      if (v is! Map) continue;

      DateTime? date;
      final ts = v['date'];
      if (ts is int) {
        final t = DateTime.fromMillisecondsSinceEpoch(ts);
        date = DateTime(t.year, t.month, t.day);
      } else if (ts is String) {
        try {
          final parts = ts.split('-').map((e) => int.parse(e)).toList();
          date = DateTime(parts[0], parts[1], parts[2]);
        } catch (_) {}
      }
      if (date == null) continue;

      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      if (date.isBefore(from) || date.isAfter(to)) continue;

      final recsRaw = (v['records'] ?? []) as List;
      final records = <_Mark>[];
      for (final r in recsRaw) {
        if (r is Map) {
          final id = (r['studentId'] ?? r['id'] ?? '').toString();
          final st = (r['status'] ?? '').toString();
          if (id.isNotEmpty) {
            records.add(_Mark(id: id, status: st));
          }
        }
      }

      list.add(_Session(
        key: k.toString(),
        date: date,
        title: (v['title'] ?? '').toString(),
        records: records,
        source: _Source.hive,
      ));
    }
    return list;
  }

  // =================== FILTROS ===================
  Future<void> _pickFrom() async {
    final r = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(_from.year - 1),
      lastDate: DateTime(_to.year + 1),
      locale: const Locale('es', 'MX'),
    );
    if (r != null) setState(() => _from = r);
    await _load();
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
    await _load();
  }

  List<_Session> _inRangeSessions() {
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return _sessions
        .where((s) => !s.date.isBefore(from) && !s.date.isAfter(to))
        .toList();
  }

  // =================== PDF helpers ===================
  String _statusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case 'A':
      case 'ASISTENCIA':
      case 'PRESENT':
        return 'A';
      case 'R':
      case 'RETARDO':
      case 'LATE':
        return 'R';
      case 'J':
      case 'JUSTIFICADO':
        return 'J';
      default:
        return 'F';
    }
  }

  Future<pw.MemoryImage> _loadLogo() async {
    final logoBytes = await rootBundle.load('assets/images/logo_cetis31.png');
    return pw.MemoryImage(logoBytes.buffer.asUint8List());
  }

  // Totales para una sesión
  _AttendanceCounters _countForSession(_Session ses) {
    final c = _AttendanceCounters();
    for (final m in ses.records) {
      switch (_statusLabel(m.status)) {
        case 'A':
          c.asistencias++;
          break;
        case 'R':
          c.retardos++;
          break;
        case 'J':
          c.justificados++;
          break;
        default:
          c.faltas++;
      }
    }
    return c;
  }

  // ====== Exportación GENERAL (rango) ======
  Future<void> _exportGeneralPdf() async {
    try {
      final logo = await _loadLogo();
      final sessions = _inRangeSessions();

      final Map<String, _AttendanceCounters> counters = {
        for (final s in _students) s.id: _AttendanceCounters()
      };
      for (final ses in sessions) {
        for (final m in ses.records) {
          final c = counters[m.id];
          if (c == null) continue;
          switch (_statusLabel(m.status)) {
            case 'A':
              c.asistencias++;
              break;
            case 'R':
              c.retardos++;
              break;
            case 'J':
              c.justificados++;
              break;
            default:
              c.faltas++;
          }
        }
      }

      final rows = <List<String>>[
        ['Matrícula', 'Nombre', 'Asist.', 'Faltas', 'Retardos', 'Justif.'],
      ];
      for (final s in _students) {
        final c = counters[s.id] ?? _AttendanceCounters();
        rows.add([
          s.id,
          s.name,
          '${c.asistencias}',
          '${c.faltas}',
          '${c.retardos}',
          '${c.justificados}',
        ]);
      }

      final dfOut = DateFormat('dd/MM/yyyy');
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          _header(logo, 'Resumen de asistencias'),
          pw.SizedBox(height: 8),
          pw.Text(
            '${widget.groupClass.subject}  ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.Text(
              'Rango: ${dfOut.format(_from)} a ${dfOut.format(_to)}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: pw.BoxDecoration(
              color: pdf.PdfColors.grey300,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            border: null,
          ),
          pw.SizedBox(height: 8),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Sesiones en rango: ${sessions.length}',
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ));

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename:
            'asistencias_${widget.groupClass.groupName}_${DateFormat('yyyyMMdd').format(_from)}_${DateFormat('yyyyMMdd').format(_to)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  // ====== Exportación por ALUMNO ======
  Future<void> _exportStudentPdf(Student s) async {
    try {
      final logo = await _loadLogo();
      final sessions = _inRangeSessions();
      final rows = <List<String>>[
        ['Fecha', 'Estado'],
      ];
      final cnt = _AttendanceCounters();
      final df = DateFormat('dd/MM/yyyy');

      for (final ses in sessions) {
        final mark = ses.records
            .firstWhere((m) => m.id == s.id, orElse: () => _Mark(id: s.id, status: 'F'));
        final lab = _statusLabel(mark.status);
        switch (lab) {
          case 'A': cnt.asistencias++; break;
          case 'R': cnt.retardos++; break;
          case 'J': cnt.justificados++; break;
          default:  cnt.faltas++;
        }
        rows.add([df.format(ses.date), lab]);
      }

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          _header(logo, 'Historial de asistencias por alumno'),
          pw.SizedBox(height: 8),
          pw.Text(
            '${widget.groupClass.subject}  ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.Text('Alumno: ${s.name}  •  Matrícula: ${s.id}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.Text('Rango: ${df.format(_from)} a ${df.format(_to)}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
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
            child: pw.Text(
                'Asistencias: ${cnt.asistencias}   •   Faltas: ${cnt.faltas}   •   Retardos: ${cnt.retardos}   •   Justificados: ${cnt.justificados}',
                style: const pw.TextStyle(fontSize: 10)),
          ),
        ],
      ));

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename:
            'asistencias_${s.id}_${DateFormat('yyyyMMdd').format(_from)}_${DateFormat('yyyyMMdd').format(_to)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  // ====== Exportación DIARIA ======
  Future<void> _exportDailyPdf(_Session ses) async {
    try {
      final logo = await _loadLogo();
      final rows = <List<String>>[
        ['Matrícula', 'Nombre', 'Estado'],
      ];
      final df = DateFormat('dd/MM/yyyy');

      for (final s in _students) {
        final m = ses.records.firstWhere(
          (r) => r.id == s.id,
          orElse: () => _Mark(id: s.id, status: 'F'),
        );
        rows.add([s.id, s.name, _statusLabel(m.status)]);
      }

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          _header(logo, 'Pase de lista diario'),
          pw.SizedBox(height: 8),
          pw.Text(
            '${widget.groupClass.subject}  ${widget.groupClass.groupName}  (${widget.groupClass.turno ?? ''} ${widget.groupClass.dia ?? ''})',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.Text('Fecha: ${df.format(ses.date)}',
              style: const pw.TextStyle(fontSize: 10)),
          if (ses.title.isNotEmpty)
            pw.Text('Sesión: ${ses.title}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
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
        filename: 'pase_lista_${DateFormat('yyyyMMdd').format(ses.date)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  // ===== Editar / Eliminar sesión =====
  Future<void> _editSessionMeta(_Session s) async {
    final df = DateFormat('dd/MM/yyyy');
    final titleCtl = TextEditingController(text: s.title);
    DateTime date = s.date;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar sesión'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtl,
              decoration: const InputDecoration(
                labelText: 'Título (opcional)',
                prefixIcon: Icon(Icons.edit_outlined),
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

    if (ok != true) return;

    try {
      if (s.source == _Source.firestore) {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        final doc = FirebaseFirestore.instance
            .collection('teachers')
            .doc(uid)
            .collection('attendance')
            .doc(_gid)
            .collection('sessions')
            .doc(s.key);
        await doc.update({
          'title': titleCtl.text.trim(),
          // guardamos como string YYYY-MM-DD para mantener compatibilidad
          'date': DateFormat('yyyy-MM-dd').format(date),
        });
      } else {
        if (!Hive.isBoxOpen(_boxName)) await Hive.openBox(_boxName);
        final box = Hive.box(_boxName);
        final value = Map<String, dynamic>.from(box.get(s.key) as Map);
        await box.put(s.key, {
          ...value,
          'title': titleCtl.text.trim(),
          'date': DateFormat('yyyy-MM-dd').format(date),
        });
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión actualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo editar: $e')),
      );
    }
  }

  Future<void> _deleteSession(_Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar sesión'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton.tonal(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      if (s.source == _Source.firestore) {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance
            .collection('teachers')
            .doc(uid)
            .collection('attendance')
            .doc(_gid)
            .collection('sessions')
            .doc(s.key)
            .delete();
      } else {
        if (!Hive.isBoxOpen(_boxName)) await Hive.openBox(_boxName);
        final box = Hive.box(_boxName);
        await box.delete(s.key);
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión eliminada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  // =================== UI ===================
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
        return StatefulBuilder(builder: (ctx, setSt) {
          final q = _studentQuery.toLowerCase();
          final list = _students
              .where((s) =>
                  s.name.toLowerCase().contains(q) ||
                  s.id.toLowerCase().contains(q))
              .toList();

          return SafeArea(
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Elegir alumno',
                          style: TextStyle(fontWeight: FontWeight.w700)),
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
        });
      },
    );

    if (res != null) {
      await _exportStudentPdf(res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    final list = _inRangeSessions();

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de asistencia')),
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
                    child: Text('Sesiones en rango: ${list.length}',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: list.isEmpty
                      ? const Center(child: Text('No hay sesiones en el rango seleccionado'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = list[i];
                            final counts = _countForSession(s);
                            // ====== CARD estilo plano (como calificaciones)
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.pink.shade50,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2.0),
                                    child: Icon(Icons.event, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          DateFormat('EEEE d \'de\' MMM, yyyy', 'es_MX').format(s.date),
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'P: ${counts.asistencias}  •  R: ${counts.retardos}  •  A: ${counts.faltas}  •  Total: ${s.records.length}',
                                          style: Theme.of(context).textTheme.bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar sesión',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _editSessionMeta(s),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar sesión',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteSession(s),
                                      ),
                                      IconButton(
                                        tooltip: 'Exportar PDF diario',
                                        icon: const Icon(Icons.picture_as_pdf_outlined),
                                        onPressed: () => _exportDailyPdf(s),
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

  // =================== helpers ===================
  pw.Widget _header(pw.ImageProvider logo, String title) => pw.Row(children: [
        pw.SizedBox(width: 48, height: 48, child: pw.Image(logo)),
        pw.SizedBox(width: 12),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Sistema CETIS 31',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
        ]),
      ]);
}

// ===== Modelos internos =====
enum _Source { firestore, hive }

class _Session {
  final String key;
  final DateTime date;
  final String title;
  final List<_Mark> records;
  final _Source source;
  _Session({
    required this.key,
    required this.date,
    required this.title,
    required this.records,
    required this.source,
  });
}

class _Mark {
  final String id; // matrícula
  final String status; // 'A','F','R','J',...
  _Mark({required this.id, required this.status});
}

class _AttendanceCounters {
  int asistencias = 0;
  int faltas = 0;
  int retardos = 0;
  int justificados = 0;
}
