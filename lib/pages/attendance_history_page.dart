import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../services/attendance_service.dart';
import 'edit_attendance_page.dart';
import 'reports_page.dart';

class AttendanceHistoryPage extends StatefulWidget {
  final GroupClass groupClass;

  const AttendanceHistoryPage({super.key, required this.groupClass});

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _sessions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await AttendanceService.instance.listSessions(
        groupId: widget.groupClass.groupName,
        limit: 500,
      );
      setState(() => _sessions = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _deleteSession(String docId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: const Text('¿Seguro que deseas eliminar esta lista de asistencia?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await AttendanceService.instance.deleteSessionById(docId: docId);
      await _loadSessions();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Lista eliminada correctamente')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        title: Text('Historial • ${widget.groupClass.groupName}'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _sessions.isEmpty
                  ? const Center(child: Text('No hay registros de asistencia aún'))
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemCount: _sessions.length,
                      itemBuilder: (_, i) {
                        final s = _sessions[i];
                        final dateStr = (s['date'] ?? '').toString();
                        final dt = DateTime.tryParse(dateStr) ?? DateTime.now();
                        final subj = (s['subject'] ?? widget.groupClass.subject);
                        final present = s['present'] ?? 0;
                        final late = s['late'] ?? 0;
                        final absent = s['absent'] ?? 0;
                        final total = s['total'] ?? 0;
                        final docId = s['docId'] ?? '';

                        return Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFDF0F1),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${df.format(dt)} • $subj',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'P: $present  •  R: $late  •  A: $absent  •  Total: $total',
                                style: TextStyle(
                                    color: Colors.grey.shade700, fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () async {
                                        final result =
                                            await Navigator.push<bool>(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => EditAttendancePage(
                                              docId: docId,
                                              subject: subj,
                                              groupName:
                                                  widget.groupClass.groupName,
                                              start:
                                                  widget.groupClass.start.format(context),
                                              end:
                                                  widget.groupClass.end.format(context),
                                              date: dt,
                                              records: List<Map<String, dynamic>>.from(
                                                  s['records'] ?? const []),
                                            ),
                                          ),
                                        );
                                        if (result == true) {
                                          await _loadSessions();
                                        }
                                      },
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Editar'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFD32F2F),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => _deleteSession(docId),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Eliminar'),
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(color: Color(0xFFD32F2F)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.assessment_outlined),
                label: const Text('Ver reportes'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ReportsPage(initialGroup: widget.groupClass),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
