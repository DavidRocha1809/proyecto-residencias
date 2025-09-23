import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../local_groups.dart' as LG;
import '../services/attendance_service.dart';
import '../models.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.initialGroup});
  final GroupClass? initialGroup;

  static const route = '/reports';

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  DateTimeRange? _range;
  String? _selectedSubject;

  bool _loading = true;
  final List<GroupClass> _allGroups = [];
  final List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    // Si viene un grupo desde la tarjeta, úsalo como "semilla"
    if (widget.initialGroup != null) {
      _allGroups.add(widget.initialGroup!);
      _selectedSubject = null; // o widget.initialGroup!.subject;
    }
    _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _range,
      locale: const Locale('es', 'MX'),
    );
    if (!mounted) return;
    if (res != null) {
      setState(() => _range = res);
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _rows.clear();
    });

    try {
      // En producción, aquí podrías cargar TODOS los grupos del docente si _allGroups está vacío
      final List<GroupClass> list =
          _selectedSubject == null
              ? _allGroups
              : _allGroups.where((g) => g.subject == _selectedSubject).toList();

      for (final g in list) {
        final gid = LG.groupKeyOf(g);
        final items = await AttendanceService.instance.listSessions(
          groupId: gid,
          limit: 500,
          dateFrom: _range?.start, // ✅ ahora existe
          dateTo: _range?.end, // ✅ ahora existe
        );
        _rows.addAll(items);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar reportes: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false); // 👈 sin "return" aquí
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            tooltip: 'Rango de fechas',
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _rows.isEmpty
              ? const Center(child: Text('Sin registros'))
              : ListView.separated(
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = _rows[i];
                  final dt =
                      DateTime.tryParse(
                        (r['date'] ?? r['id']) as String? ?? '',
                      ) ??
                      DateTime.now();
                  final subj = (r['subject'] ?? '').toString();
                  final gname = (r['groupName'] ?? '').toString();
                  final present = r['present'] ?? r['presentCount'] ?? '';
                  return ListTile(
                    title: Text('$subj — $gname'),
                    subtitle: Text(
                      'Fecha: ${df.format(dt)}  •  Presentes: $present',
                    ),
                  );
                },
              ),
    );
  }
}
