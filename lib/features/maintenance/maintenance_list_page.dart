import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/role_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/maintenance_reminder_service.dart';
import '../../models/maintenance_schedule_model.dart';
import '../../repositories/maintenance_repository.dart';
import '../../widgets/error_utils.dart';

class MaintenanceListPage extends ConsumerWidget {
  const MaintenanceListPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
  final my = user == null ? const AsyncValue<List<MaintenanceSchedule>>.data([]) : ref.watch(myMaintenanceProvider(user.uid));
  final roleAsync = ref.watch(userRoleProvider);
  final canManage = roleAsync.canManageKnowledge; // reuse engineer/admin check
    final upcoming = ref.watch(upcomingMaintenanceProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance Schedules'),
        actions: [
          if (user != null)
            IconButton(
              tooltip: 'Run reminders',
              icon: const Icon(Icons.notifications_active_outlined),
              onPressed: () async {
                try {
                  final sent = await ref.read(maintenanceReminderServiceProvider).runCallable();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Reminders requested ($sent scheduled).')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    showFriendlyError(context, e, fallback: 'Could not request reminders. Please try again.');
                  }
                }
              },
            ),
        ],
      ),
      floatingActionButton: (user != null && canManage)
          ? FloatingActionButton(
              onPressed: () async {
                await showDialog(context: context, builder: (_) => const _NewMaintenanceDialog());
              },
              child: const Icon(Icons.add),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(upcomingMaintenanceProvider);
          if (user != null) ref.invalidate(myMaintenanceProvider(user.uid));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const Text('Assigned to Me', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _Section(list: my, emptyText: 'No active assignments'),
            const SizedBox(height: 20),
            const Text('All Upcoming', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _Section(list: upcoming, emptyText: 'No upcoming maintenance'),
          ],
        ),
      ),
    );
  }

  // Removed permissive _canCreate; role-based gating now handled in build.
}

class _Section extends ConsumerWidget {
  final AsyncValue<List<MaintenanceSchedule>> list;
  final String emptyText;
  const _Section({required this.list, required this.emptyText});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return list.when(
      data: (items) {
        if (items.isEmpty) return _Empty(text: emptyText);
        return Column(
          children: [
            for (final s in items) _Tile(s: s),
          ],
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
      error: (e, _) => FriendlyErrorView(error: e, onRetry: () => ref.invalidate(upcomingMaintenanceProvider)),
    );
  }
}

class _Tile extends ConsumerWidget {
  final MaintenanceSchedule s;
  const _Tile({required this.s});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = s.dueDate;
    final days = due.difference(DateTime.now()).inDays;
    final color = s.completed
        ? Colors.grey
        : (days < 0
            ? Colors.red
            : (days <= 3 ? Colors.orange : Colors.green));
    return Card(
      child: ListTile(
        leading: Icon(Icons.event_available_outlined, color: color),
        title: Text('Equipment: ${s.equipmentId}'),
        subtitle: Text('Due: ${due.toLocal()} • Assigned: ${s.assignedTo}${s.completed ? ' • Completed' : ''}'),
        trailing: s.completed
            ? null
            : IconButton(
                tooltip: 'Mark completed',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () async {
                  try {
                    await ref.read(maintenanceRepositoryProvider).markCompleted(s.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked complete')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showFriendlyError(context, e, fallback: 'Could not update. Please try again.');
                    }
                  }
                },
              ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        alignment: Alignment.center,
        child: Text(text, style: const TextStyle(color: Colors.black54)),
      );
}

class _NewMaintenanceDialog extends ConsumerStatefulWidget {
  const _NewMaintenanceDialog();
  @override
  ConsumerState<_NewMaintenanceDialog> createState() => _NewMaintenanceDialogState();
}

class _NewMaintenanceDialogState extends ConsumerState<_NewMaintenanceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _equipmentId = TextEditingController();
  final _assignedTo = TextEditingController();
  DateTime? _dueDate;

  @override
  void dispose() {
    _equipmentId.dispose();
    _assignedTo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Maintenance'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _equipmentId,
              decoration: const InputDecoration(labelText: 'Equipment ID'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _assignedTo,
              decoration: const InputDecoration(labelText: 'Assign to (uid)'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(_dueDate == null ? 'Pick due date' : _dueDate!.toLocal().toString().split('.').first)),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now.add(const Duration(days: 1)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _dueDate = DateTime(picked.year, picked.month, picked.day));
                    }
                  },
                  child: const Text('Pick'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate() || _dueDate == null) return;
            try {
              final id = await ref.read(maintenanceRepositoryProvider).create(
                    MaintenanceSchedule(
                      id: '',
                      equipmentId: _equipmentId.text.trim(),
                      dueDate: _dueDate!,
                      assignedTo: _assignedTo.text.trim(),
                      completed: false,
                    ),
                  );
              if (context.mounted) {
                Navigator.of(context).pop(id);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Created')));
              }
            } catch (e) {
              if (context.mounted) {
                showFriendlyError(context, e, fallback: 'Could not create item. Please try again.');
              }
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
