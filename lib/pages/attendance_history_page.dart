// … imports …
import 'edit_attendance_page.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../local_store.dart'; // <- si lo sigues usando en otras opciones
import '../utils/attendance_pdf.dart'; // <- NUEVO (PDF por alumno)
import 'package:flutter/material.dart';

class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({
    super.key,
    required this.groupId,
    this.subjectName,
  });

  static const route = '/attendance-history';

  final String groupId;
  final String? subjectName;

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  final _rows = <Map<String, dynamic>>[];
  bool _loading = true;

  DateTimeRange _range = DateTimeRange(
    start: DateTime(DateTime.now().year, DateTime.now().month, 1),
    end: DateTime(DateTime.now().year, DateTime.now().month + 1, 0),
  );

  final dfHuman = DateFormat("EEEE d 'de' MMM',' yyyy", 'es_MX');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 1, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      initialDateRange: _range,
      locale: const Locale('es', 'MX'),
      helpText: 'Selecciona rango de días',
      saveText: 'Aplicar',
    );
    if (picked == null) return;
    setState(() => _range = picked);
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows.clear();
    });

    try {
      final items = await AttendanceService.instance.listSessions(
        groupId: widget.groupId,
        limit: 1000,
        dateFrom: _range.start,
        dateTo: _range.end,
      );
      _rows.addAll(items);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo cargar el historial: $e')));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// 🔄 Exporta el PDF GENERAL por **alumno** (A, R, F) con logo.
  Future<void> _exportRangePdf() async {
    try {
      await AttendancePdf.exportSummaryByStudent(
        groupId: widget.groupId,
        subject: widget.subjectName,
        from: _range.start,
        to: _range.end,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  // ===== Eliminar =====
  Future<void> _onDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Eliminar sesión'),
            content: Text(
              '¿Eliminar la sesión del ${(row['date'] ?? row['docId']).toString()}?\n'
              'Esta acción no se puede deshacer.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      final docId = (row['docId'] ?? row['id']).toString();
      await AttendanceService.instance.deleteSessionById(
        groupId: widget.groupId,
        docId: docId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sesión eliminada')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
    }
  }

  // ===== Editar =====
  Future<void> _onEdit(Map<String, dynamic> row) async {
    try {
      final dt = DateTime.tryParse((row['date'] ?? row['docId']).toString()) ?? DateTime.now();
      final full = await AttendanceService.instance.getSessionByGroupAndDate(
        groupId: widget.groupId,
        date: dt,
      );
      if (full == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('No se encontró la sesión.')));
        return;
      }

      final changed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => EditAttendancePage(
            groupId: widget.groupId,
            docId: (full['docId'] ?? row['docId']).toString(),
            subject: (full['subject'] ?? row['subject'] ?? '').toString(),
            groupName: (full['groupName'] ?? row['groupName'] ?? '').toString(),
            start: (full['start'] ?? row['start'] ?? '--:--').toString(),
            end: (full['end'] ?? row['end'] ?? '--:--').toString(),
            date: dt,
            records: ((full['records'] as List?) ?? const [])
                .map<Map<String, dynamic>>((e) =>
                    e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{})
                .toList(),
          ),
        ),
      );

      if (changed == true) {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo abrir la edición: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final periodLabel =
        '${DateFormat("d 'de' MMM 'de' yyyy", 'es_MX').format(_range.start)}  —  '
        '${DateFormat("d 'de' MMM 'de' yyyy", 'es_MX').format(_range.end)}';

    final surfaceHigh = Theme.of(context).colorScheme.surfaceVariant;
    final surfaceLow = Theme.of(context).colorScheme.surface;

    return Scaffold(
      appBar: AppBar(title: const Text('Historial de asistencia')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: _pickRange,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: surfaceHigh,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.date_range),
                        const SizedBox(width: 8),
                        Expanded(child: Text(periodLabel, overflow: TextOverflow.ellipsis)),
                        const Icon(Icons.keyboard_arrow_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _exportRangePdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Exportar PDF (filtro actual)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('Sin registros'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final dateStr = (r['date'] ?? r['docId'] ?? '').toString();
                          final dt = DateTime.tryParse(dateStr) ?? DateTime.now();
                          final present = (r['present'] ?? r['presentCount'] ?? 0) as int;
                          final late = (r['late'] ?? 0) as int;
                          final absent = (r['absent'] ?? 0) as int;
                          final total = (r['total'] ?? (present + late + absent)) as int;

                          return Material(
                            color: surfaceLow,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(dfHuman.format(dt),
                                  style: Theme.of(context).textTheme.titleMedium),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('P: $present  •  R: $late  •  A: $absent  •  Total: $total'),
                              ),
                              trailing: Wrap(
                                spacing: 6,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _onEdit(r),
                                  ),
                                  IconButton(
                                    tooltip: 'Eliminar',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _onDelete(r),
                                  ),
                                  IconButton(
                                    tooltip: 'PDF (este día)',
                                    icon: const Icon(Icons.picture_as_pdf_outlined),
                                    onPressed: () async {
                                      try {
                                        await LocalStore.exportSessionPdfSmart(
                                          groupId: widget.groupId,
                                          date: dt,
                                          subject: widget.subjectName,
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('No se pudo exportar: $e')),
                                        );
                                      }
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
    );
  }
}
