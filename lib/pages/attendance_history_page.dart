// lib/pages/attendance_history_page.dart
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../local_groups.dart' as LG;

import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart' as pdf;
import 'package:flutter/services.dart' show rootBundle;

// Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Servicio (para borrar y otras utilidades que ya tengas)
import '../services/attendance_service.dart';

// 👇 tu editor existente
import 'edit_attendance_page.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final String groupId;
  final String? subjectName;

  const AttendanceHistoryPage({
    super.key,
    required this.groupId,
    this.subjectName,
  });

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  bool _loading = true;
  List<Student> _students = [];
  List<_Session> _sessions = [];

  // metadatos para mostrar en el editor
  String _metaGroupName = '';
  String _metaSubject = '';
  String _metaStart = '';
  String _metaEnd = '';

  String get _logBox => 'attendance_log::${widget.groupId}';

  // ---- helpers para formatear horas (TimeOfDay → "HH:mm")
  String _two(int n) => n.toString().padLeft(2, '0');
  String _fmtTime(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      await _loadGroupMeta();

      final studs = await LG.LocalGroups.listStudents(groupId: widget.groupId)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      final cloud = await _loadFromFirestore();
      final list = cloud.isNotEmpty ? cloud : await _loadFromHive();

      if (!mounted) return;
      setState(() {
        _students = studs;
        _sessions = list..sort((a, b) => a.date.compareTo(b.date));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo cargar: $e')));
    }
  }

  Future<void> _loadGroupMeta() async {
    try {
      final all = await LG.LocalGroups.listGroups();
      final g = all.firstWhere(
        (x) => LG.groupKeyOf(x) == widget.groupId,
        orElse: () => GroupClass(
          groupName: '',
          subject: widget.subjectName ?? '',
          turno: null,
          dia: null,
          // ✅ start/end son TimeOfDay en tu modelo
          start: const TimeOfDay(hour: 7, minute: 0),
          end:   const TimeOfDay(hour: 8, minute: 0),
          students: const [],
        ),
      );
      _metaGroupName = g.groupName;
      _metaSubject = g.subject;
      _metaStart = _fmtTime(g.start); // ✅ a String "HH:mm"
      _metaEnd = _fmtTime(g.end);     // ✅ a String "HH:mm"
    } catch (_) {}
  }

  // ---------- Firestore ----------
  Future<List<_Session>> _loadFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final col = FirebaseFirestore.instance
        .collection('teachers')
        .doc(uid)
        .collection('attendance')
        .doc(widget.groupId)
        .collection('sessions');

    final snap = await col.get();
    final out = <_Session>[];

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

      out.add(_Session(
        key: d.id,
        date: date,
        attendance: Map<String, dynamic>.from(m['attendance'] ?? const {}),
        source: _Src.firestore,
        raw: m,
      ));
    }
    return out;
  }

  // ---------- Hive ----------
  Future<List<_Session>> _loadFromHive() async {
    if (!Hive.isBoxOpen(_logBox)) await Hive.openBox(_logBox);
    final box = Hive.box(_logBox);
    final out = <_Session>[];

    for (final k in box.keys) {
      final v = box.get(k);
      if (v is! Map) continue;

      DateTime? date;
      final raw = v['date'];
      if (raw is int) {
        final d = DateTime.fromMillisecondsSinceEpoch(raw);
        date = DateTime(d.year, d.month, d.day);
      } else if (raw is String && raw.isNotEmpty) {
        try {
          final p = raw.split('-').map((e) => int.parse(e)).toList();
          date = DateTime(p[0], p[1], p[2]);
        } catch (_) {}
      }
      if (date == null) continue;

      final from = DateTime(_from.year, _from.month, _from.day);
      final to = DateTime(_to.year, _to.month, _to.day);
      if (date.isBefore(from) || date.isAfter(to)) continue;

      out.add(_Session(
        key: k.toString(),
        date: date,
        attendance: Map<String, dynamic>.from(v['attendance'] ?? const {}),
        source: _Src.hive,
        raw: v,
      ));
    }
    return out;
  }

  // ===== Helpers =====
  List<_Session> _inRange() {
    final from = DateTime(_from.year, _from.month, _from.day);
    final to = DateTime(_to.year, _to.month, _to.day);
    return _sessions
        .where((s) => !s.date.isBefore(from) && !s.date.isAfter(to))
        .toList();
  }

  Map<String, int> _countTotals(Map<String, dynamic> map) {
    int p = 0, r = 0, a = 0;
    map.forEach((_, v) {
      final s = v?.toString().toUpperCase() ?? '';
      if (s.startsWith('P') || s == '1') {
        p++;
      } else if (s.startsWith('R') || s == '2') {
        r++;
      } else if (s.startsWith('A') || s == '0') {
        a++;
      }
    });
    return {'P': p, 'R': r, 'A': a};
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

  // ====== EDITAR (abre tu editor con el mismo diseño del pase de lista) ======
  List<Map<String, dynamic>> _buildEditRecords(_Session s) {
    // mapeamos asistencia a 'present' | 'late' | 'absent' que espera EditAttendancePage
    return _students.map((st) {
      final raw = (s.attendance[st.id] ?? '').toString().toUpperCase().trim();
      final status =
          (raw.startsWith('P') || raw == '1') ? 'present' :
          (raw.startsWith('R') || raw == '2') ? 'late'    :
          (raw.startsWith('A') || raw == '0') ? 'absent'  :
          'present';
      return {
        'studentId': st.id,
        'name': st.name,
        'status': status,
      };
    }).toList();
  }

  Future<void> _openEditor(_Session s) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditAttendancePage(
          groupId: widget.groupId,
          docId: s.key, // yyyy-MM-dd
          subject: _metaSubject,
          groupName: _metaGroupName,
          start: _metaStart,
          end: _metaEnd,
          date: s.date,
          records: _buildEditRecords(s),
        ),
      ),
    );
    if (changed == true) {
      await _loadAll();
    }
  }

  // ====== ELIMINAR (igual que antes) ======
  Future<void> _deleteSession(_Session s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar sesión'),
        content: const Text('Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await AttendanceService.instance
          .deleteSessionById(groupId: widget.groupId, docId: s.key);
      await _loadAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sesión eliminada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  // ====== PDF ======
  Future<pw.MemoryImage> _loadLogo() async {
    final bytes = await rootBundle.load('assets/images/logo_cetis31.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  Future<void> _exportGeneralPdf() async {
    try {
      final logo = await _loadLogo();
      final df = DateFormat('dd/MM/yyyy');

      final data = _inRange();
      final doc = pw.Document();

      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(children: [
            pw.SizedBox(width: 48, height: 48, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Sistema CETIS 31',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Historial de asistencia', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('Grupo: $_metaGroupName   •   Materia: $_metaSubject',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Rango: ${df.format(_from)} a ${df.format(_to)}',
              style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 10),
          ...data.map((s) {
            final c = _countTotals(s.attendance);
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(df.format(s.date)),
                  pw.Text('P: ${c['P']}  •  R: ${c['R']}  •  A: ${c['A']}'),
                ],
              ),
            );
          }),
        ],
      ));

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'asistencia_${_metaGroupName}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  Future<void> _exportSessionPdf(_Session s) async {
    try {
      final logo = await _loadLogo();
      final df = DateFormat('dd/MM/yyyy');

      final rows = <List<String>>[
        ['Matrícula', 'Nombre', 'Estado'],
      ];
      for (final st in _students) {
        final raw = (s.attendance[st.id] ?? '').toString().toUpperCase();
        String estado =
            raw.startsWith('P') || raw == '1' ? 'Presente' :
            raw.startsWith('R') || raw == '2' ? 'Retardo' :
            raw.startsWith('A') || raw == '0' ? 'Ausente'  : '';
        rows.add([st.id, st.name, estado]);
      }

      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Row(children: [
            pw.SizedBox(width: 48, height: 48, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Sistema CETIS 31',
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Pase de lista', style: const pw.TextStyle(fontSize: 12)),
            ]),
          ]),
          pw.SizedBox(height: 8),
          pw.Text('Grupo: $_metaGroupName   •   Materia: $_metaSubject',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Fecha: ${df.format(s.date)}',
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
        ],
      ));

      await Printing.sharePdf(
        bytes: await doc.save(),
        filename: 'asistencia_${DateFormat('yyyyMMdd').format(s.date)}.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo generar el PDF: $e')));
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEEE d \'de\' MMM, y', 'es_MX');
    final inRange = _inRange();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de asistencia'),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _exportGeneralPdf,
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
                          label: Text(
                              'Desde: ${DateFormat('dd/MM/yyyy').format(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickTo,
                          icon: const Icon(Icons.event_available),
                          label: Text(
                              'Hasta: ${DateFormat('dd/MM/yyyy').format(_to)}'),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Sesiones en rango: ${inRange.length}',
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
                const Divider(height: 0),
                Expanded(
                  child: inRange.isEmpty
                      ? const Center(
                          child:
                              Text('No hay sesiones en el rango seleccionado'))
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: inRange.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = inRange[i];
                            final c = _countTotals(s.attendance);

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.pink.shade50,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.event_note, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          df.format(s.date),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                            'P: ${c['P']}  •  R: ${c['R']}  •  A: ${c['A']}  •  Total: ${_students.length}'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar',
                                        icon: const Icon(Icons.edit_outlined),
                                        onPressed: () => _openEditor(s),
                                      ),
                                      IconButton(
                                        tooltip: 'Eliminar',
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => _deleteSession(s),
                                      ),
                                      IconButton(
                                        tooltip: 'PDF',
                                        icon: const Icon(
                                            Icons.picture_as_pdf_outlined),
                                        onPressed: () => _exportSessionPdf(s),
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
}

// ====== Modelo interno ======
enum _Src { firestore, hive }

class _Session {
  final String key; // yyyy-MM-dd (o similar)
  final DateTime date;
  final Map<String, dynamic> attendance;
  final _Src source;
  final Object? raw;

  _Session({
    required this.key,
    required this.date,
    required this.attendance,
    required this.source,
    this.raw,
  });
}
