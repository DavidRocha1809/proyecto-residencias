import 'package:flutter/material.dart';
import '../models.dart';
import '../local_groups.dart' as LG;
import 'attendance_history_page.dart';

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key, required this.groups});

  // Lista de grupos (puede venir de tu servicio o de Firebase)
  final List<GroupClass> groups;

  static const route = '/sessions';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sesiones'),
      ),
      body: groups.isEmpty
          ? const Center(child: Text('No tienes grupos asignados'))
          : ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final groupClass = groups[i];
                return ListTile(
                  title: Text(groupClass.subject),
                  subtitle: Text(groupClass.groupName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // 👉 Aquí abrimos el historial al tocar el grupo
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceHistoryPage(
                          groupId: LG.groupKeyOf(groupClass),
                          subjectName: groupClass.subject,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
