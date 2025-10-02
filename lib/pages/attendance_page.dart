import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../local_groups.dart' as LG;
import '../local_store.dart';
import '../services/attendance_service.dart';

class AttendancePage extends StatefulWidget {
  static const route = '/attendance';
  final GroupClass groupClass;
  final DateTime initialDate;
  const AttendancePage({
    super.key,
    required this.groupClass,
    required this.initialDate,
  });

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  DateTime _date = DateTime.now();
  List<Student> _students = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _loadStudents();
  }

  Future<void> _loadStudents() async {
    try {
      final gid = LG.groupKeyOf(widget.groupClass);
      final list = await LG.LocalGroups.listStudents(groupId: gid);
      if (!mounted) return;
      setState(() {
        _students = list
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar alumnos: $e')),
      );
    }
  }

  // ===== helpers visuales =====
  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Color get _presentColor => const Color(0xFF2E7D32); // verde
  Color get _lateColor => const Color(0xFFF9A825); // ámbar
  Color get _absentColor => const Color(0xFFC62828); // rojo
  Color get _muted => Theme.of(context).colorScheme.outlineVariant;

  // ===== contadores =====
  int get _countPresent =>
      _students.where((s) => s.status == AttendanceStatus.present).length;
  int get _countLate =>
      _students.where((s) => s.status == AttendanceStatus.late).length;
  int get _countAbsent =>
      _students.where((s) => s.status == AttendanceStatus.absent).length;
  int get _countTotal => _students.length;

  void _setAllPresent() {
    setState(() {
      for (final s in _students) {
        s.status = AttendanceStatus.present;
      }
    });
  }

  Future<void> _pickDate() async {
    final res = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(_date.year - 1),
      lastDate: DateTime(_date.year + 1),
      locale: const Locale('es', 'MX'),
    );
    if (res != null) setState(() => _date = res);
  }

  Future<void> _save() async {
    try {
      // 1) local (Hive)
      await LocalStore.saveTodaySession(
        groupClass: widget.groupClass,
        date: _date,
        students: _students,
      );
      // 2) Firestore
      await AttendanceService.instance.saveSessionToFirestore(
        groupId: LG.groupKeyOf(widget.groupClass),
        subject: widget.groupClass.subject,
        groupName: widget.groupClass.groupName,
        start: _fmtTime(widget.groupClass.start),
        end: _fmtTime(widget.groupClass.end),
        date: _date,
        records: _students
            .map((s) => {
                  'studentId': s.id,
                  'name': s.name,
                  'status': switch (s.status) {
                    AttendanceStatus.present => 'present',
                    AttendanceStatus.late => 'late',
                    AttendanceStatus.absent => 'absent',
                    _ => 'none',
                  },
                })
            .toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lista guardada con éxito')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al guardar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d/M/yyyy');
    final filtered = _query.trim().isEmpty
        ? _students
        : _students.where((s) {
            final q = _query.toLowerCase();
            return s.name.toLowerCase().contains(q) ||
                s.id.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.groupClass.subject,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.groupClass.groupName} • ${_fmtTime(widget.groupClass.start)} - ${_fmtTime(widget.groupClass.end)}\n${df.format(_date)}',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: FilledButton.icon(
              onPressed: _students.isEmpty ? null : _setAllPresent,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD32F2F), // rojo del diseño
                minimumSize: const Size(10, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.check),
              label: const Text('Todos Presentes'),
            ),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _students.isEmpty ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F), // rojo
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.save),
            label: const Text('Guardar Lista de Asistencia'),
          ),
        ),
      ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // barra de contadores estilo chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _CounterChip(
                        color: _presentColor,
                        label: 'Presentes',
                        value: _countPresent,
                      ),
                      _CounterChip(
                        color: _lateColor,
                        label: 'Retardos',
                        value: _countLate,
                      ),
                      _CounterChip(
                        color: _absentColor,
                        label: 'Ausentes',
                        value: _countAbsent,
                      ),
                      _CounterChip(
                        color: _muted,
                        label: 'Total',
                        value: _countTotal,
                      ),
                    ],
                  ),
                ),

                // buscador
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Buscar estudiante…',
                      isDense: true,
                    ),
                  ),
                ),

                // fecha (tap para cambiar)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.event),
                      label: Text('Fecha: ${df.format(_date)}'),
                    ),
                  ),
                ),

                // lista
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Sin alumnos'))
                      : ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = filtered[i];
                            return _StudentCard(
                              student: s,
                              presentColor: _presentColor,
                              lateColor: _lateColor,
                              absentColor: _absentColor,
                              onStatus: (st) =>
                                  setState(() => s.status = st),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

// ===== Widgets de UI =====

class _CounterChip extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _CounterChip({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text('$value $label',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
  final Student student;
  final Color presentColor, lateColor, absentColor;
  final ValueChanged<AttendanceStatus> onStatus;

  const _StudentCard({
    required this.student,
    required this.presentColor,
    required this.lateColor,
    required this.absentColor,
    required this.onStatus,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.outline;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // nombre + id
            Text(
              student.name,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'ID: ${student.id}',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: muted),
            ),
            const SizedBox(height: 10),

            // 3 botones grandes
            Row(
              children: [
                _StatusButton(
                  icon: Icons.check,
                  color: presentColor,
                  selected: student.status == AttendanceStatus.present,
                  onTap: () => onStatus(AttendanceStatus.present),
                ),
                const SizedBox(width: 12),
                _StatusButton(
                  icon: Icons.schedule,
                  color: lateColor,
                  selected: student.status == AttendanceStatus.late,
                  onTap: () => onStatus(AttendanceStatus.late),
                ),
                const SizedBox(width: 12),
                _StatusButton(
                  icon: Icons.close,
                  color: absentColor,
                  selected: student.status == AttendanceStatus.absent,
                  onTap: () => onStatus(AttendanceStatus.absent),
                ),
              ],
            ),

            const SizedBox(height: 10),
            // etiqueta de estado
            Row(
              children: [
                const Icon(Icons.radio_button_unchecked, size: 18),
                const SizedBox(width: 6),
                Text(
                  switch (student.status) {
                    AttendanceStatus.present => 'Presente',
                    AttendanceStatus.late => 'Retardo',
                    AttendanceStatus.absent => 'Ausente',
                    _ => 'Sin marcar',
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _StatusButton({
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? color.withOpacity(.15)
        : Theme.of(context).colorScheme.surfaceVariant;
    final border = selected ? color : Colors.transparent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: border, width: 2),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}
