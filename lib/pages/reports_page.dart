import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/attendance_service.dart';
import '../models.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../local_store.dart';

enum ReportPeriod { daily, weekly, monthly }

class ReportsPage extends StatefulWidget {
  static const route = '/reports'; // 👈 ruta

  const ReportsPage({super.key, this.initialGroup});
  final GroupClass? initialGroup;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportPeriod _period = ReportPeriod.daily;
  DateTime _anchor = DateTime.now();

  DateTimeRange? _range;
  bool _loading = true;
  final List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _recomputeRange();
    _load();
  }

  void _recomputeRange() {
    final d = DateTime(_anchor.year, _anchor.month, _anchor.day);
    switch (_period) {
      case ReportPeriod.daily:
        _range = DateTimeRange(start: d, end: d);
        break;
      case ReportPeriod.weekly:
        final start = d.subtract(Duration(days: d.weekday - 1)); // lunes
        final end = start.add(const Duration(days: 6)); // domingo
        _range = DateTimeRange(start: start, end: end);
        break;
      case ReportPeriod.monthly:
        final start = DateTime(d.year, d.month, 1);
        final end = DateTime(d.year, d.month + 1, 0);
        _range = DateTimeRange(start: start, end: end);
        break;
    }
  }

  Future<void> _pickAnchorDate() async {
    final res = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(DateTime.now().year - 1, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
      locale: const Locale('es', 'MX'),
    );
    if (res == null) return;
    setState(() {
      _anchor = res;
      _recomputeRange();
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows.clear();
    });

    try {
      // 🔹 Leer todas las sesiones del docente desde Firestore
      final sessions = await AttendanceService.instance.listSessions(
        groupId: widget.initialGroup?.groupName ?? '',
        limit: 500,
      );

      // 🔹 Filtrar las que estén dentro del rango seleccionado
      final filtered = sessions.where((s) {
        final date = (s['date'] is Timestamp)
            ? (s['date'] as Timestamp).toDate()
            : DateTime.tryParse(s['date'].toString()) ?? DateTime.now();
        return date.isAfter(_range!.start.subtract(const Duration(days: 1))) &&
            date.isBefore(_range!.end.add(const Duration(days: 1)));
      }).toList();

      setState(() {
        _rows.addAll(filtered);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar reportes: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    try {
      if (_rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No hay registros para exportar')),
        );
        return;
      }

      final title = switch (_period) {
        ReportPeriod.daily => 'Reporte Diario',
        ReportPeriod.weekly => 'Reporte Semanal',
        ReportPeriod.monthly => 'Reporte Mensual',
      };

      await LocalStore.exportPeriodPdf(
        from: _range!.start,
        to: _range!.end,
        rows: List<Map<String, dynamic>>.from(_rows),
        titulo: title,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF "$title" generado correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');
    final dfHuman = DateFormat("d 'de' MMMM 'de' yyyy", 'es_MX');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            tooltip: 'Exportar PDF (rango actual)',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportPdf,
          ),
          IconButton(
            tooltip: 'Cambiar fecha ancla',
            icon: const Icon(Icons.date_range),
            onPressed: _pickAnchorDate,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                SegmentedButton<ReportPeriod>(
                  segments: const [
                    ButtonSegment(
                      value: ReportPeriod.daily,
                      label: Text('Diario'),
                      icon: Icon(Icons.today_outlined),
                    ),
                    ButtonSegment(
                      value: ReportPeriod.weekly,
                      label: Text('Semanal'),
                      icon: Icon(Icons.calendar_view_week),
                    ),
                    ButtonSegment(
                      value: ReportPeriod.monthly,
                      label: Text('Mensual'),
                      icon: Icon(Icons.calendar_month_outlined),
                    ),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) async {
                    setState(() {
                      _period = s.first;
                      _recomputeRange();
                    });
                    await _load();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _range == null
                        ? ''
                        : 'Periodo: ${dfHuman.format(_range!.start)} — ${dfHuman.format(_range!.end)}',
                    overflow: TextOverflow.ellipsis,
                  ),
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
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final dt = (r['date'] is Timestamp)
                              ? (r['date'] as Timestamp).toDate()
                              : DateTime.tryParse(r['date'].toString()) ??
                                  DateTime.now();

                          final subj = (r['subject'] ?? '').toString();
                          final gname = (r['groupName'] ?? '').toString();
                          final present = r['present'] ?? 0;
                          final late = r['late'] ?? 0;
                          final absent = r['absent'] ?? 0;
                          final total = r['total'] ?? (present + late + absent);

                          return ListTile(
                            title: Text(
                              subj.isEmpty
                                  ? 'Grupo: $gname'
                                  : '$subj — $gname',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Fecha: ${df.format(dt)}  •  P: $present  R: $late  A: $absent  •  Total: $total',
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
