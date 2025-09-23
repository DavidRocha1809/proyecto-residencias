import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/attendance_service.dart';
import '../local_store.dart';
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
      final docs = await AttendanceService.instance.listSessions(
        groupId: groupId,
        limit: 100,
      );
      _items = docs;
    } catch (e) {
      _items = [];
      if (mounted) {
        final msg = e.toString().contains('permission-denied')
            ? 'No tienes permisos para ver el historial. Revisa autenticación y Reglas.'
            : 'No se pudo cargar historial: $e';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _exportPdf(Map<String, dynamic> item) async {
    try {
      final String ymd = (item['date'] ?? item['yyyymmdd'] ?? '').toString();
      final date = ymd.length >= 10 ? DateTime.parse(ymd.substring(0, 10)) : DateTime.now();
      await LocalStore.exportTodayPdfFallback(widget.groupClass, date);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar PDF: $e')),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    try {
      final String ymd = (item['date'] ?? item['yyyymmdd'] ?? '').toString();
      final date = ymd.length >= 10 ? DateTime.parse(ymd.substring(0, 10)) : DateTime.now();
      final groupId = LG.groupKeyOf(widget.groupClass);

      final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Eliminar registro'),
              content: Text('¿Eliminar definitivamente la sesión del $ymd?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
              ],
            ),
          ) ??
          false;
      if (!ok) return;

      await AttendanceService.instance.deleteAttendance(
        groupId: groupId,
        yyyymmdd: ymd.substring(0, 10),
      );
      await LocalStore.removeSession(classId: groupId, date: date);

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registro eliminado ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat("EEEE d 'de' MMMM, yyyy", 'es_MX');

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Historial de asistencia'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (_, i) {
                final it = _items[i];
                final String ymd = (it['date'] ?? it['yyyymmdd'] ?? '').toString();
                final date = ymd.length >= 10 ? DateTime.parse(ymd.substring(0, 10)) : DateTime.now();
                final present = it['present'] ?? it['P'] ?? 0;
                final late = it['late'] ?? it['R'] ?? 0;
                final absent = it['absent'] ?? it['A'] ?? 0;
                final total = it['total'] ?? it['T'] ?? (present + late + absent);

                return Card(
                  color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(.4),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    title: Text(df.format(date)),
                    subtitle: Text('P: $present · R: $late · A: $absent · Total: $total'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'Exportar a PDF',
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          onPressed: () => _exportPdf(it),
                        ),
                        IconButton(
                          tooltip: 'Editar',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AttendancePage(
                                  groupClass: widget.groupClass,
                                  initialDate: date,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(it),
                        ),
                      ],
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: _items.length,
            ),
    );
  }
}
