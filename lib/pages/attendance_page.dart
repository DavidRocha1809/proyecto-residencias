import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../local_store.dart';
import '../services/attendance_service.dart';
import '../local_groups.dart' as lg; // alias minúscula

class AttendancePage extends StatefulWidget {
  static const route = '/attendance';
  final GroupClass groupClass;

  const AttendancePage({
    super.key,
    required this.groupClass,
    required DateTime initialDate, // (si lo pasas desde el Dashboard)
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  String search = '';
  bool _loading = true;

  bool _loadingSession = false;
  bool _hasExisting = false;

  DateTime _date = DateTime.now();

  List<Student> _students = [];

  int get present =>
      _students.where((s) => s.status == AttendanceStatus.present).length;
  int get late =>
      _students.where((s) => s.status == AttendanceStatus.late).length;
  int get absent =>
      _students.where((s) => s.status == AttendanceStatus.absent).length;
  int get total => _students.length;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 1) Origen de alumnos
    if (widget.groupClass.students.isNotEmpty) {
      _students = List<Student>.from(widget.groupClass.students);
    } else {
      final groupId = lg.groupKeyOf(widget.groupClass);
      _students = await lg.getStudents(groupId);
    }

    // DEDUPE en memoria por id (por si ya había duplicados guardados)
    final seen = <String>{};
    _students = _students.where((s) => seen.add(s.id)).toList();

    // 2) Intenta cargar la sesión existente para la fecha
    await _loadExistingSessionFor(_date);

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _loadExistingSessionFor(DateTime date) async {
    setState(() {
      _loadingSession = true;
      _hasExisting = false;
    });

    final groupId = lg.groupKeyOf(widget.groupClass);

    // Busca una sesión EXACTA para 'date'
    final sessions = await AttendanceService.instance.listSessions(
      groupId: groupId,
      limit: 1,
      dateFrom: date,
      dateTo: date,
    );

    if (sessions.isNotEmpty) {
      final raw = sessions.first;

      final List rawStudents =
          (raw['students'] as List?) ?? const <Map<String, dynamic>>[];
      final Map<String, String> byId = {
        for (final m in rawStudents)
          ((m['studentId'] ?? m['matricula'] ?? '').toString()):
              (m['status'] ?? 'none').toString(),
      };

      for (final s in _students) {
        final code = byId[s.id] ?? 'none';
        s.status = _statusFromCode(code);
      }
      _hasExisting = true;
    } else {
      for (final s in _students) {
        s.status = AttendanceStatus.none;
      }
      _hasExisting = false;
    }

    if (!mounted) return;
    setState(() => _loadingSession = false);
  }

  void _setAll(AttendanceStatus st) {
    setState(() {
      for (final s in _students) {
        s.status = st;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered =
        _students
            .where((s) => s.name.toLowerCase().contains(search.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.groupClass.subject,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${widget.groupClass.groupName} • ${fmtTime(widget.groupClass.start)} - ${fmtTime(widget.groupClass.end)}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            if (widget.groupClass.turno != null ||
                widget.groupClass.dia != null)
              Text(
                '${widget.groupClass.turno ?? ''}'
                '${(widget.groupClass.turno != null && widget.groupClass.dia != null) ? ' • ' : ''}'
                '${widget.groupClass.dia ?? ''}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonal(
              onPressed: () => _setAll(AttendanceStatus.present),
              child: const Text('Todos Presentes'),
            ),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  if (_loadingSession)
                    const LinearProgressIndicator(minHeight: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        _legendDot(Colors.green, 'Presentes', present),
                        const SizedBox(width: 12),
                        _legendDot(Colors.orange, 'Retardos', late),
                        const SizedBox(width: 12),
                        _legendDot(Colors.red, 'Ausentes', absent),
                        const Spacer(),
                        Text(
                          '$total Total',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      onChanged: (v) => setState(() => search = v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Buscar estudiante…',
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      itemBuilder:
                          (_, i) => _StudentRow(
                            student: filtered[i],
                            onChange:
                                (st) => setState(() {
                                  final idx = _students.indexWhere(
                                    (s) => s.id == filtered[i].id,
                                  );
                                  if (idx >= 0) _students[idx].status = st;
                                  filtered[i].status = st;
                                }),
                          ),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemCount: filtered.length,
                    ),
                  ),
                ],
              ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: _loading ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _hasExisting
                  ? 'Actualizar Lista de Asistencia'
                  : 'Guardar Lista de Asistencia',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    try {
      final today = _date;

      // 1) Guardado local (Hive) — usa la lista ACTUAL
      await LocalStore.saveTodaySession(
        groupClass: widget.groupClass,
        date: today,
        students: _students, // <- clave para que se guarde lo marcado
      );

      // 2) Firebase
      final yyyymmdd = DateFormat('yyyy-MM-dd').format(today);
      final groupId = lg.groupKeyOf(widget.groupClass);

      // DEDUPE adicional por seguridad antes de subir a Firebase
      final seen = <String>{};
      final students =
          _students
              .where((s) => seen.add(s.id))
              .map(
                (s) => {
                  'studentId': s.id,
                  'name': s.name,
                  'status': _statusCode(s.status),
                },
              )
              .toList();

      await AttendanceService.instance.saveAttendance(
        groupId: groupId,
        yyyymmdd: yyyymmdd,
        students: students,
        sessionMeta: {
          'subject': widget.groupClass.subject,
          'groupName': widget.groupClass.groupName,
          'schedule':
              '${fmtTime(widget.groupClass.start)}-${fmtTime(widget.groupClass.end)}',
          'total': students.length,
          if (widget.groupClass.turno != null) 'turno': widget.groupClass.turno,
          if (widget.groupClass.dia != null) 'dia': widget.groupClass.dia,
        },
      );

      if (!mounted) return;
      setState(() => _hasExisting = true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista guardada/actualizada ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar/sincronizar: $e')),
      );
    }
  }

  // -------- helpers --------
  Widget _legendDot(Color c, String label, int n) => Row(
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text('$n $label'),
    ],
  );

  String _statusCode(AttendanceStatus st) {
    switch (st) {
      case AttendanceStatus.present:
        return 'present';
      case AttendanceStatus.late:
        return 'late';
      case AttendanceStatus.absent:
        return 'absent';
      case AttendanceStatus.none:
        return 'none';
    }
  }

  AttendanceStatus _statusFromCode(String code) {
    switch (code) {
      case 'present':
        return AttendanceStatus.present;
      case 'late':
        return AttendanceStatus.late;
      case 'absent':
        return AttendanceStatus.absent;
      default:
        return AttendanceStatus.none;
    }
  }
}

class _StudentRow extends StatelessWidget {
  final Student student;
  final ValueChanged<AttendanceStatus> onChange;
  const _StudentRow({required this.student, required this.onChange});

  @override
  Widget build(BuildContext context) {
    Widget statusIcon(AttendanceStatus st, IconData icon, Color color) {
      final isSelected = student.status == st;
      return IconButton(
        tooltip: st.name,
        onPressed: () => onChange(st),
        icon: Icon(icon, color: isSelected ? color : color.withOpacity(.35)),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: CircleAvatar(child: Text(student.name.characters.first)),
        title: Text(
          student.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('ID: ${student.id} • ${_statusText(student.status)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            statusIcon(
              AttendanceStatus.present,
              Icons.check_circle,
              Colors.green,
            ),
            statusIcon(
              AttendanceStatus.late,
              Icons.access_time_filled,
              Colors.orange,
            ),
            statusIcon(AttendanceStatus.absent, Icons.cancel, Colors.red),
          ],
        ),
      ),
    );
  }

  String _statusText(AttendanceStatus st) {
    switch (st) {
      case AttendanceStatus.present:
        return 'Presente';
      case AttendanceStatus.late:
        return 'Retardo';
      case AttendanceStatus.absent:
        return 'Ausente';
      case AttendanceStatus.none:
        return 'Sin marcar';
    }
  }
}
