import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models.dart';
import 'student_selection_page.dart';

import '../services/grades_service.dart';
import '../utils/grades_pdf.dart'; // ✅ tu PDF está aquí
import 'grades_capture_page.dart';

class GradesHistoryPage extends StatefulWidget {
  final GroupClass groupClass;

  const GradesHistoryPage({super.key, required this.groupClass});

  @override
  State<GradesHistoryPage> createState() => _GradesHistoryPageState();
}

class _GradesHistoryPageState extends State<GradesHistoryPage> {
  final _firestore = FirebaseFirestore.instance;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  bool _loading = true;
  List<Map<String, dynamic>> _activities = [];

  String get _groupId => widget.groupClass.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // 🔹 Cargar todas las actividades del grupo
  Future<void> _load() async {
    setState(() => _loading = true);
    print('📤 Iniciando carga de actividades para $_groupId');
    print('📅 Rango: ${_from.toIso8601String()} -> ${_to.toIso8601String()}');

    try {
      // 🔹 Obtener las actividades crudas desde Firestore
      final List<Map<String, dynamic>> raw =
          await GradesService.listActivitiesRaw(groupId: _groupId);

      print('📦 Actividades obtenidas: ${raw.length}');
      for (final a in raw) {
        print(
          '📝 Documento: ${a['id']} | Fecha: ${a['date']} | Nombre: ${a['activity']}',
        );
      }

      // 🔹 Normalizar límites de fecha (día completo)
      final from = DateTime(_from.year, _from.month, _from.day, 0, 0, 0);
      final to = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);

      print('📅 Normalizado: from=$from  to=$to');

      // 🔹 Filtrar por rango inclusivo
      final filtered =
          raw.where((a) {
            try {
              final dateStr = a['date']?.toString() ?? '';
              if (dateStr.isEmpty) {
                print('⚠️ Documento sin fecha: ${a['id']}');
                return false;
              }

              final d = DateFormat('yyyy-MM-dd').parse(dateStr);
              final date = DateTime(d.year, d.month, d.day);
              final include = !date.isBefore(from) && !date.isAfter(to);

              print(
                '🔎 ${a['id']} => $date → ${include ? "✅ DENTRO" : "❌ FUERA"}',
              );
              return include;
            } catch (e) {
              print('❌ Error parseando fecha en ${a['id']}: $e');
              return false;
            }
          }).toList();

      print('🎯 Actividades filtradas: ${filtered.length}');

      setState(() {
        _activities = filtered;
        _loading = false;
      });
    } catch (e) {
      print('💥 Error general al cargar: $e');
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar actividades: $e')),
      );
    }
  }

  Future<void> _pickDateRange(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'MX'),
    );

    if (picked == null) return;

    setState(() {
      if (isFrom) {
        _from = picked;
        if (_from.isAfter(_to)) _to = _from;
      } else {
        _to = picked;
        if (_to.isBefore(_from)) _from = _to;
      }
    });

    await _load();
  }

  // 🔹 Eliminar una actividad
  Future<void> _deleteActivity(Map<String, dynamic> activity) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Eliminar actividad'),
            content: const Text('¿Seguro que deseas eliminar esta actividad?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      await GradesService.deleteActivity(
        groupId: _groupId,
        activityId: activity['id'] ?? '', // ✅ coincide con tu servicio
      );

      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Actividad eliminada correctamente')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    }
  }

  // 🔹 Exportar PDF (usa tu utils/attendance_pdf.dart)
  Future<void> _exportPdf() async {
    try {
      await GradesPdf.exportSummaryByStudent(
        groupId: _groupId,
        subject: widget.groupClass.subject,
        groupName: widget.groupClass.groupName,
        from: _from,
        to: _to,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al exportar PDF: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Historial de calificaciones – ${widget.groupClass.groupName}',
        ),
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🔹 Filtros de fecha
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDateRange(true),
                            icon: const Icon(Icons.date_range),
                            label: Text('Desde: ${df.format(_from)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickDateRange(false),
                            icon: const Icon(Icons.date_range),
                            label: Text('Hasta: ${df.format(_to)}'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Actividades en rango: ${_activities.length}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 12),

                    // 🔹 Lista de actividades
                    Expanded(
                      child:
                          _activities.isEmpty
                              ? const Center(
                                child: Text(
                                  'No hay actividades registradas en este rango.',
                                ),
                              )
                              : ListView.builder(
                                itemCount: _activities.length,
                                itemBuilder: (context, i) {
                                  final item = _activities[i];
                                  final date = (item['date'] ?? '').toString();
                                  final actDate =
                                      date.isNotEmpty
                                          ? DateFormat('yyyy-MM-dd').parse(date)
                                          : DateTime.now();

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.pink.shade50,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: ListTile(
                                      leading: const Icon(
                                        Icons.assignment_outlined,
                                        color: Colors.black54,
                                      ),
                                      title: Text(
                                        item['activity'] ?? 'Actividad',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(df.format(actDate)),
                                      trailing: Wrap(
                                        spacing: 8,
                                        children: [
                                          IconButton(
                                            tooltip: 'Editar',
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder:
                                                      (_) => GradesCapturePage(
                                                        existing: item,
                                                        groupClass:
                                                            widget.groupClass,
                                                      ),
                                                ),
                                              ).then((_) => _load());
                                            },
                                          ),
                                          IconButton(
                                            tooltip: 'Eliminar',
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                            onPressed:
                                                () => _deleteActivity(item),
                                          ),
                                          IconButton(
                                            tooltip:
                                                'Exportar PDF de esta actividad',
                                            icon: const Icon(
                                              Icons.picture_as_pdf_outlined,
                                            ),
                                            onPressed: () async {
                                              print(
                                                '🧾 Exportando PDF de una sola actividad...',
                                              );
                                              final activityId =
                                                  item['id'] ?? '';
                                              final activityName =
                                                  item['activity'] ??
                                                  'Sin nombre';
                                              print(
                                                '🧭 activityId: $activityId | activityName: $activityName',
                                              );

                                              try {
                                                await GradesPdf.exportSingleActivity(
                                                  groupId: _groupId,
                                                  activityId: activityId,
                                                  activityName: activityName,
                                                  subject:
                                                      widget.groupClass.subject,
                                                  groupName:
                                                      widget
                                                          .groupClass
                                                          .groupName,
                                                );
                                              } catch (e) {
                                                print(
                                                  '💥 Error al exportar PDF individual: $e',
                                                );
                                                if (!mounted) return;
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Error al exportar PDF: $e',
                                                    ),
                                                  ),
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

                    // 🔹 Botón inferior PDF general
                    SafeArea(
                      minimum: const EdgeInsets.only(top: 12),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Exportar PDF'),
                          onPressed: () async {
                            // 🔹 Mostrar menú emergente
                            final option = await showModalBottomSheet<String>(
                              context: context,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20),
                                ),
                              ),
                              builder:
                                  (_) => Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Exportar PDF',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const Divider(),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.assessment_outlined,
                                          color: Colors.teal,
                                        ),
                                        title: const Text(
                                          'Exportar resumen general',
                                        ),
                                        onTap:
                                            () => Navigator.pop(
                                              context,
                                              'general',
                                            ),
                                      ),
                                      ListTile(
                                        leading: const Icon(
                                          Icons.person_outline,
                                          color: Colors.indigo,
                                        ),
                                        title: const Text(
                                          'Exportar por alumno',
                                        ),
                                        onTap:
                                            () => Navigator.pop(
                                              context,
                                              'student',
                                            ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ),
                            );

                            if (option == 'general') {
                              // ✅ Exportación general (rango actual)
                              await GradesPdf.exportSummaryByStudent(
                                groupId: _groupId,
                                subject: widget.groupClass.subject,
                                groupName: widget.groupClass.groupName,
                                from: _from,
                                to: _to,
                              );
                            } else if (option == 'student') {
                              // 👩‍🏫 Navegar a nueva página
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) => StudentSelectionPage(
                                        groupClass: widget.groupClass,
                                        from: _from,
                                        to: _to,
                                      ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}
