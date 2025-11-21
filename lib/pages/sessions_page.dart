// lib/pages/sessions_page.dart
import 'package:flutter/material.dart';
import '../models.dart';


import 'attendance_history_page.dart' show AttendanceHistoryPage;

class SessionsPage extends StatefulWidget {
  /// Pueden venir uno o varios grupos (variantes turno/día).
  final List<GroupClass> groups;

  /// Si hay exactamente 1 grupo, saltar directo al historial.
  final bool autoSkipSingle;

  const SessionsPage({
    super.key,
    required this.groups,
    this.autoSkipSingle = true,
  });

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  @override
  void initState() {
    super.initState();

    // Autoredirigir si sólo hay un grupo
    if (widget.autoSkipSingle && widget.groups.length == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final g = widget.groups.first;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => AttendanceHistoryPage(
              groupName: g.groupName,
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Evita parpadeo si redirigimos
    if (widget.autoSkipSingle && widget.groups.length == 1) {
      return const SizedBox.shrink();
    }

    // Si hay varios grupos, muestra lista para elegir
    return Scaffold(
      appBar: AppBar(title: const Text('Sesiones')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: widget.groups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final g = widget.groups[i];
          return Card(
            child: ListTile(
              title: Text(g.subject),
              subtitle: Text(g.groupName),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AttendanceHistoryPage(
                      groupName: g.groupName,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
