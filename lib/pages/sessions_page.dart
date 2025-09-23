import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/attendance_service.dart';
import '../local_groups.dart' as LG;
import 'attendance_page.dart';

class SessionsPage extends StatefulWidget {
  static const route = '/sessions';
  final GroupClass groupClass;

  const SessionsPage({super.key, required this.groupClass});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groupId = LG.groupKeyOf(widget.groupClass);
      _items = await AttendanceService.instance.listSessions(
        groupId: groupId,
        limit: 200,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _delete(String yyyymmdd) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('Eliminar sesión'),
                content: Text('¿Eliminar el pase de lista del $yyyymmdd?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Eliminar'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!ok) return;

    final groupId = LG.groupKeyOf(widget.groupClass);
    await AttendanceService.instance.deleteAttendance(
      groupId: groupId,
      yyyymmdd: yyyymmdd,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sesión eliminada')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de asistencia')),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                onRefresh: _load,
                child:
                    _items.isEmpty
                        ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 180),
                            Center(child: Text('Sin sesiones')),
                          ],
                        )
                        : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _items.length,
                          separatorBuilder:
                              (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final it = _items[i];
                            final id = (it['id'] as String); // yyyymmdd
                            final dt = DateTime.parse(id);
                            final dateStr = DateFormat(
                              'EEEE d MMM, y',
                              'es_MX',
                            ).format(dt);
                            final present = it['present'] ?? 0;
                            final late = it['late'] ?? 0;
                            final absent = it['absent'] ?? 0;
                            final total = it['total'] ?? 0;

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                title: Text(
                                  dateStr,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'P: $present  •  R: $late  •  A: $absent  •  Total: $total',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Abrir para editar',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder:
                                                (_) => AttendancePage(
                                                  groupClass: widget.groupClass,
                                                  // ⚠️ Requiere que AttendancePage acepte este parámetro opcional:
                                                  // final DateTime? initialDate;
                                                  // y que lo use para cargar la sesión existente.
                                                  initialDate: dt,
                                                ),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      tooltip: 'Eliminar',
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () => _delete(id),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
              ),
    );
  }
}
