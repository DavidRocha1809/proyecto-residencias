import 'package:flutter/material.dart';
import '../services/attendance_service.dart';

enum _St { present, late, absent }

class EditAttendancePage extends StatefulWidget {
  const EditAttendancePage({
    super.key,
    required this.docId,      // groupId_fecha
    required this.subject,
    required this.groupName,
    required this.start,
    required this.end,
    required this.date,
    required this.records,    // [{studentId,name,status}]
  });

  final String docId;
  final String subject;
  final String groupName;
  final String start;
  final String end;
  final DateTime date;
  final List<Map<String, dynamic>> records;

  @override
  State<EditAttendancePage> createState() => _EditAttendancePageState();
}

class _EditAttendancePageState extends State<EditAttendancePage> {
  late List<_Row> _rows;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _rows = widget.records
        .map((e) => _Row(
              id: (e['studentId'] ?? '').toString(),
              name: (e['name'] ?? '').toString(),
              status: _parse((e['status'] ?? 'present').toString()),
            ))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  // ===== Helpers =====
  static _St _parse(String v) {
    switch (v) {
      case 'late':
        return _St.late;
      case 'absent':
        return _St.absent;
      default:
        return _St.present;
    }
  }

  static String _statusToString(_St s) =>
      s == _St.present ? 'present' : s == _St.late ? 'late' : 'absent';

  List<_Row> get _filtered {
    if (_query.trim().isEmpty) return _rows;
    final q = _query.toLowerCase();
    return _rows
        .where((r) =>
            r.name.toLowerCase().contains(q) || r.id.toLowerCase().contains(q))
        .toList();
  }

  int get _present => _rows.where((r) => r.status == _St.present).length;
  int get _late => _rows.where((r) => r.status == _St.late).length;
  int get _absent => _rows.where((r) => r.status == _St.absent).length;

  void _setAllPresent() {
    setState(() {
      for (final r in _rows) {
        r.status = _St.present;
      }
    });
  }

  Future<void> _save() async {
    try {
      final payload = _rows
          .map((r) => {
                'studentId': r.id,
                'name': r.name,
                'status': _statusToString(r.status),
              })
          .toList();

      // ✅ Ajuste: ya no se usa groupId
      await AttendanceService.instance.updateSessionById(
        docId: widget.docId,
        records: payload,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cambios guardados correctamente')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo guardar: $e')),
      );
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final surfaceHigh = cs.surfaceVariant;
    final surfaceLow = cs.surface;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subject} • ${widget.groupName}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton(
              onPressed: _setAllPresent,
              child: const Text('Todos Presentes'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // resumen chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _chip(context, 'Presentes', _present, Colors.green),
                _chip(context, 'Retardos', _late, Colors.orange),
                _chip(context, 'Ausentes', _absent, Colors.red),
                _chip(context, 'Total', _rows.length, Colors.grey),
              ],
            ),
          ),
          // buscador
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar estudiante…',
                border: UnderlineInputBorder(),
              ),
            ),
          ),
          // fecha/hora (solo display)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.date.day}/${widget.date.month}/${widget.date.year}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.start.isNotEmpty || widget.end.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: surfaceHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.access_time),
                        const SizedBox(width: 8),
                        Text('${widget.start} — ${widget.end}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // lista
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: _filtered.length,
              itemBuilder: (_, i) {
                final r = _filtered[i];
                return Material(
                  color: surfaceLow,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // nombre + id
                        Text(
                          r.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text('ID: ${r.id}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 12),
                        // tres botones de estado
                        Row(
                          children: [
                            _stateButton(
                              context: context,
                              isSelected: r.status == _St.present,
                              icon: Icons.check_circle_outline,
                              onTap: () =>
                                  setState(() => r.status = _St.present),
                            ),
                            const SizedBox(width: 12),
                            _stateButton(
                              context: context,
                              isSelected: r.status == _St.late,
                              icon: Icons.schedule_outlined,
                              onTap: () => setState(() => r.status = _St.late),
                            ),
                            const SizedBox(width: 12),
                            _stateButton(
                              context: context,
                              isSelected: r.status == _St.absent,
                              icon: Icons.cancel_outlined,
                              onTap: () =>
                                  setState(() => r.status = _St.absent),
                            ),
                            const Spacer(),
                            // etiqueta de estado
                            Row(
                              children: [
                                Icon(
                                  Icons.radio_button_off,
                                  size: 18,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _statusLabel(r.status),
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar Lista de Asistencia'),
          ),
        ),
      ),
    );
  }

  // ===== widgets auxiliares =====
  Widget _chip(BuildContext context, String label, int value, Color color) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: TextStyle(color: cs.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _stateButton({
    required BuildContext context,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? cs.primary.withOpacity(.12) : cs.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Icon(
          icon,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
    );
  }

  String _statusLabel(_St s) {
    switch (s) {
      case _St.present:
        return 'Presente';
      case _St.late:
        return 'Retardo';
      case _St.absent:
        return 'Ausente';
    }
  }
}

class _Row {
  _Row({required this.id, required this.name, required this.status});
  final String id;
  final String name;
  _St status;
}
