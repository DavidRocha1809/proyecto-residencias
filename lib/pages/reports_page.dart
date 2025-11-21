import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models.dart';
import '../services/attendance_service.dart';
import '../utils/attendance_pdf.dart';

enum ReportPeriod { daily, weekly, monthly }

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.initialGroup});
  final GroupClass? initialGroup;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportPeriod _period = ReportPeriod.daily;
  DateTime _anchor = DateTime.now();
  DateTimeRange? _range;
  bool _loading = false;
  final List<Map<String, dynamic>> _rows = [];

  void _recomputeRange() {
    final d = DateTime(_anchor.year, _anchor.month, _anchor.day);
    switch (_period) {
      case ReportPeriod.daily:
        _range = DateTimeRange(start: d, end: d);
        break;
      case ReportPeriod.weekly:
        final start = d.subtract(Duration(days: d.weekday - 1));
        final end = start.add(const Duration(days: 6));
        _range = DateTimeRange(start: start, end: end);
        break;
      case ReportPeriod.monthly:
        final start = DateTime(d.year, d.month, 1);
        final end = DateTime(d.year, d.month + 1, 0);
        _range = DateTimeRange(start: start, end: end);
        break;
    }
  }

  @override
  void initState() {
    super.initState();
    _recomputeRange();
    _load();
  }

  Future<void> _load() async {
    if (_range == null) return;
    setState(() {
      _loading = true;
      _rows.clear();
    });

    try {
      final sessions = await AttendanceService.instance.listSessions(
        groupId: widget.initialGroup?.groupName ?? '',
        dateFrom: _range!.start,
        dateTo: _range!.end,
      );
      setState(() => _rows.addAll(sessions));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar reportes: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _exportPdf() async {
    if (widget.initialGroup == null || _rows.isEmpty) return;
    await AttendancePdf.exportSummaryByStudent(
      groupId: widget.initialGroup!.groupName,
      subject: widget.initialGroup!.subject,
      groupName: widget.initialGroup!.groupName,
      from: _range!.start,
      to: _range!.end,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dfHuman = DateFormat("d 'de' MMMM 'de' yyyy", 'es_MX');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes de asistencia'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: _exportPdf,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('Sin registros'))
              : ListView.builder(
                  itemCount: _rows.length,
                  itemBuilder: (_, i) {
                    final r = _rows[i];
                    final date = (r['date'] is Timestamp)
                        ? (r['date'] as Timestamp).toDate()
                        : DateTime.tryParse(r['date'].toString()) ??
                            DateTime.now();
                    return ListTile(
                      title: Text(r['groupName'] ?? ''),
                      subtitle: Text(
                          '${r['subject']} • ${dfHuman.format(date)} • ${r['records']?.length ?? 0} alumnos'),
                    );
                  },
                ),
    );
  }
}
