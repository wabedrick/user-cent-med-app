import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../main.dart' show debugRoleOverrideProvider; // Auth screens split
import '../auth/sign_in_screen.dart';
// Removed shared DashboardShell; using dedicated header + sidebar for Nurse
import '../repositories/repair_requests_repository.dart';
import '../models/repair_request_model.dart';
import '../repositories/user_repository.dart';
import '../repositories/equipment_repository.dart';
import '../widgets/error_utils.dart';

enum Urgency { low, medium, high }

class NurseTaskSummary {
  final String equipmentName;
  final String note;
  final Urgency urgency;
  NurseTaskSummary(this.equipmentName, this.note, {required this.urgency});
}

class QuickStats {
  final int assigned;
  final int dueSoon;
  final int overdue;
  final int resolvedToday;
  const QuickStats({required this.assigned, required this.dueSoon, required this.overdue, required this.resolvedToday});
}

// Mock providers (later wire to Firestore)
final nurseTasksProvider = FutureProvider<List<NurseTaskSummary>>((ref) async {
  await Future.delayed(const Duration(milliseconds: 350));
  return [
    NurseTaskSummary('Infusion Pump', 'Tubing replacement due', urgency: Urgency.medium),
    NurseTaskSummary('Ventilator', 'Filter check overdue', urgency: Urgency.high),
    NurseTaskSummary('ECG Monitor', 'Running nominal', urgency: Urgency.low),
  ];
});

final quickStatsProvider = FutureProvider<QuickStats>((ref) async {
  await Future.delayed(const Duration(milliseconds: 250));
  return const QuickStats(assigned: 12, dueSoon: 3, overdue: 1, resolvedToday: 5);
});

class NurseDashboardScreen extends ConsumerStatefulWidget {
  const NurseDashboardScreen({super.key});
  @override
  ConsumerState<NurseDashboardScreen> createState() => _NurseDashboardScreenState();
}

class _NurseDashboardScreenState extends ConsumerState<NurseDashboardScreen> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final titles = const ['Overview', 'Requests', 'History', 'Profile'];
    final title = titles[(tab >= 0 && tab < titles.length) ? tab : 0];
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 900;

    return Scaffold(
      drawer: isNarrow
          ? Drawer(
              child: SafeArea(
                child: _NurseSideNav(
                  currentIndex: tab,
                  onSelect: (i) {
                    setState(() => tab = i);
                    Navigator.of(context).maybePop();
                  },
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!isNarrow)
              SizedBox(
                width: 220,
                child: _NurseSideNav(
                  currentIndex: tab,
                  onSelect: (i) => setState(() => tab = i),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _NurseHeaderBar(
                    title: title,
                    showMenu: isNarrow,
                  ),
                  const Divider(height: 1),
                  Expanded(child: _NurseBody(tab: tab)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NurseBody extends ConsumerWidget {
  final int tab;
  const _NurseBody({required this.tab});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(quickStatsProvider);
    final tasks = ref.watch(nurseTasksProvider);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1200;

    Widget statsRow() {
      return stats.when(
        data: (s) {
          final cards = [
            _StatCard(label: 'Assigned', value: s.assigned.toString(), icon: Icons.assignment_turned_in_outlined, color: AppColors.primary),
            _StatCard(label: 'Due Soon', value: s.dueSoon.toString(), icon: Icons.watch_later_outlined, color: AppColors.warning),
            _StatCard(label: 'Overdue', value: s.overdue.toString(), icon: Icons.error_outline, color: AppColors.error),
            _StatCard(label: 'Resolved Today', value: s.resolvedToday.toString(), icon: Icons.task_alt, color: AppColors.success),
          ];
          List<Widget> rows = [];
          for (var i = 0; i < cards.length; i += 2) {
            final rowChildren = <Widget>[Expanded(child: cards[i])];
            if (i + 1 < cards.length) {
              rowChildren.add(const SizedBox(width: 18));
              rowChildren.add(Expanded(child: cards[i + 1]));
            } else {
              rowChildren.add(const Spacer());
            }
            rows.add(Row(children: rowChildren));
            if (i + 2 < cards.length) rows.add(const SizedBox(height: 18));
          }
          return Column(children: rows);
        },
        loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
  error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(quickStatsProvider)),
      );
    }

    Widget tasksList() {
      return tasks.when(
        data: (list) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: list.isEmpty
              ? _EmptyState(
                  key: const ValueKey('empty'),
                  icon: Icons.check_circle_outline,
                  title: 'All Clear',
                  message: 'No outstanding maintenance indicators right now.',
                )
              : ListView.separated(
                  key: const ValueKey('list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _TaskTile(item: list[i]),
                ),
        ),
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator()),
        ),
  error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(nurseTasksProvider)),
      );
    }

    Widget overview() {
      final content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Today Overview', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 18),
            statsRow(),
            const SizedBox(height: 36),
            Row(
              children: [
                Text('Equipment Attention', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(onPressed: () {}, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
              ],
            ),
            const SizedBox(height: 12),
            tasksList(),
            const SizedBox(height: 44),
            Text('Recent Activity', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _RecentActivityList(isWide: isWide),
            const SizedBox(height: 96),
          ],
        ),
      );
      if (isWide) {
        return Row(children: [Expanded(child: content), const SizedBox(width: 360, child: _RightPanel())]);
      }
      return content;
    }

    Widget placeholder(String title) => Center(child: Text('$title (static)', style: Theme.of(context).textTheme.titleLarge));

    switch (tab) {
      case 0:
        return overview();
      case 1:
        return const _RequestsTab();
      case 2:
        return placeholder('History');
      case 3:
        return placeholder('Profile');
      default:
        return overview();
    }
  }
}

class _RequestsTab extends ConsumerWidget {
  const _RequestsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Not signed in'));
    }
    final myReqs = ref.watch(myRepairRequestsProvider(user.uid));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: Row(
            children: [
              Text('My Repair Requests', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  await showDialog(context: context, builder: (_) => const _NewRequestDialog());
                },
                icon: const Icon(Icons.add),
                label: const Text('New Request'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: myReqs.when(
            data: (list) {
              if (list.isEmpty) {
                return const _EmptyState(icon: Icons.check_circle_outline, title: 'No Requests', message: 'You have not created any requests yet.');
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (ctx, i) => _RequestTile(item: list[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(myRepairRequestsProvider(user.uid))),
          ),
        ),
      ],
    );
  }
}

class _RequestTile extends ConsumerWidget {
  final RepairRequest item;
  const _RequestTile({required this.item});
  Color _statusColor() {
    switch (item.status) {
      case 'open':
        return AppColors.warning;
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
        return AppColors.success;
      case 'closed':
        return Colors.grey;
      default:
        return AppColors.primary;
    }
  }
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userByIdProvider(item.reportedByUserId));
    final reporter = user.maybeWhen(data: (u) => u?.displayName ?? u?.email ?? 'Unknown', orElse: () => '…');
    AsyncValue<String?> equipmentNameAv;
    if (item.equipmentId.isEmpty) {
      equipmentNameAv = const AsyncValue.data(null);
    } else {
      final eq = ref.watch(equipmentByIdProvider(item.equipmentId));
      equipmentNameAv = eq.whenData((e) => e?.name);
    }
    final equipmentName = equipmentNameAv.maybeWhen(data: (n) => n ?? 'Unknown equipment', orElse: () => '…');
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: _statusColor().withValues(alpha: 0.12), child: Icon(Icons.build_outlined, color: _statusColor())),
        title: Text(item.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('Eq: $equipmentName • By: $reporter • Status: ${item.status}${item.assignedEngineerId != null ? ' • Assigned' : ''}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {},
      ),
    );
  }
}

class _NewRequestDialog extends ConsumerStatefulWidget {
  const _NewRequestDialog();
  @override
  ConsumerState<_NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends ConsumerState<_NewRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  String? _equipmentId;
  String? _equipmentName;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Repair Request'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Describe the issue'),
              minLines: 2,
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a description' : null,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDialog<({String id, String name})>(context: context, builder: (_) => const _EquipmentPickerDialog());
                  if (picked != null) {
                    setState(() {
                      _equipmentId = picked.id;
                      _equipmentName = picked.name;
                    });
                  }
                },
                icon: const Icon(Icons.precision_manufacturing_outlined),
                label: Text(_equipmentName == null ? 'Select Equipment (optional)' : 'Selected: $_equipmentName'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);
            try {
              await ref.read(repairRequestsRepositoryProvider).create(
                    equipmentId: _equipmentId ?? '',
                    reportedByUserId: user.uid,
                    description: _descCtrl.text.trim(),
                  );
              if (!mounted) return;
              navigator.pop();
              messenger.showSnackBar(const SnackBar(content: Text('Request created')));
            } catch (e) {
              showFriendlyError(context, e, fallback: 'Could not submit.');
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EquipmentPickerDialog extends ConsumerStatefulWidget {
  const _EquipmentPickerDialog();
  @override
  ConsumerState<_EquipmentPickerDialog> createState() => _EquipmentPickerDialogState();
}

class _EquipmentPickerDialogState extends ConsumerState<_EquipmentPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(equipmentListProvider);
    return AlertDialog(
      title: const Text('Select Equipment'),
      content: LayoutBuilder(builder: (ctx, constraints) {
        final screenW = MediaQuery.of(ctx).size.width;
        final dialogW = screenW > 560 ? 520.0 : (screenW - 40).clamp(280.0, 520.0);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogW),
          child: SizedBox(
            width: dialogW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 12),
                SizedBox(
                  height: 360,
                  child: list.when(
                    data: (items) {
                      final f = _q.isEmpty
                          ? items
                          : items.where((e) => e.name.toLowerCase().contains(_q) || e.model.toLowerCase().contains(_q) || e.manufacturer.toLowerCase().contains(_q)).toList();
                      if (f.isEmpty) return const Center(child: Text('No results'));
                      return ListView.separated(
                        itemCount: f.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final e = f[i];
                          return ListTile(
                            leading: const Icon(Icons.precision_manufacturing_outlined),
                            title: Text(e.name),
                            subtitle: Text('${e.manufacturer} • ${e.model}'),
                            onTap: () => Navigator.of(context).pop((id: e.id, name: e.name)),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Couldn’t load details')), 
                  ),
                ),
            ],
          ),
          ),
        );
      }),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 14),
            Text(value, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 26, color: color)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final NurseTaskSummary item;
  const _TaskTile({required this.item});
  Color _urgencyColor() {
    switch (item.urgency) {
      case Urgency.low:
        return AppColors.mint;
      case Urgency.medium:
        return AppColors.warning;
      case Urgency.high:
        return AppColors.error;
    }
  }
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: _urgencyColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.medical_services_outlined, color: _urgencyColor()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.equipmentName, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(item.note, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _urgencyColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(item.urgency.name.toUpperCase(), style: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600, fontSize: 11, color: _urgencyColor())),
            ),
            const SizedBox(width: 4),
            IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
      ),
    );
  }
}

class _RecentActivityList extends StatelessWidget {
  final bool isWide;
  const _RecentActivityList({required this.isWide});
  @override
  Widget build(BuildContext context) {
    final entries = List.generate(
      6,
      (i) => _ActivityEntry(
        icon: Icons.build_circle_outlined,
        title: 'Repair ticket #${2450 + i} updated',
        time: '${i + 1}h ago',
        detail: i.isEven ? 'Status changed to In Progress' : 'Technician assigned',
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in entries) ...[
              _ActivityTile(entry: e),
              if (e != entries.last) const Divider(height: 28),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.history), label: const Text('Full activity log')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityEntry {
  final IconData icon;
  final String title;
  final String detail;
  final String time;
  _ActivityEntry({required this.icon, required this.title, required this.detail, required this.time});
}

class _ActivityTile extends StatelessWidget {
  final _ActivityEntry entry;
  const _ActivityTile({required this.entry});
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(entry.icon, color: AppColors.primary),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(entry.title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 4),
              Text(entry.detail, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(entry.time, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600])),
      ],
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(left: BorderSide(color: AppColors.outline)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(-2, 0)),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: const [
          _PanelSection(
            title: 'Quick Actions',
            children: [
              _QuickAction(icon: Icons.add_circle_outline, label: 'New Request'),
              _QuickAction(icon: Icons.qr_code_scanner, label: 'Scan Asset'),
              _QuickAction(icon: Icons.assignment_turned_in_outlined, label: 'Log Usage'),
            ],
          ),
          SizedBox(height: 32),
          _PanelSection(
            title: 'Reminders',
            children: [
              _ReminderChip(text: 'Calibrate AED tomorrow'),
              _ReminderChip(text: 'Sterilization audit 14:00'),
              _ReminderChip(text: 'Pump battery swap (2 units)'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _PanelSection({required this.title, required this.children});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.primaryDark)),
        const SizedBox(height: 16),
        Wrap(runSpacing: 12, spacing: 12, children: children),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  const _QuickAction({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Ink(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)).borderRadius,
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(label, style: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ReminderChip extends StatelessWidget {
  final String text;
  const _ReminderChip({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.alarm, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(text, style: GoogleFonts.sourceSans3(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({super.key, required this.icon, required this.title, required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(icon, size: 56, color: AppColors.primaryLight),
          const SizedBox(height: 24),
          Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.primaryDark)),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ErrorInline extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorInline({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
            TextButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = FirebaseAuth.instance.currentUser?.email;
    final initial = (email != null && email.isNotEmpty) ? email.characters.first.toUpperCase() : null;
    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == 'debug_engineer') {
          ref.read(debugRoleOverrideProvider).setRole('engineer');
          return;
        } else if (value == 'debug_admin') {
          ref.read(debugRoleOverrideProvider).setRole('admin');
          return;
        } else if (value == 'debug_clear') {
          ref.read(debugRoleOverrideProvider).clear();
          return;
        } else if (value == 'logout') {
          try {
            await FirebaseAuth.instance.signOut();
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const SignInScreen()),
              (route) => false,
            );
          } catch (e) {
            if (context.mounted) {
              showFriendlyError(context, e, fallback: 'Logout failed. Please try again.');
            }
          }
        }
      },
      itemBuilder: (ctx) => [
        const PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'))),
        const PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
        const PopupMenuDivider(),
        // Debug role switching (local override)
        const PopupMenuItem(value: 'debug_engineer', child: ListTile(leading: Icon(Icons.engineering), title: Text('[Debug] Engineer View'))),
        const PopupMenuItem(value: 'debug_nurse', child: ListTile(leading: Icon(Icons.local_hospital), title: Text('[Debug] Nurse View'))),
        const PopupMenuItem(value: 'debug_admin', child: ListTile(leading: Icon(Icons.admin_panel_settings), title: Text('[Debug] Admin View'))),
        const PopupMenuItem(value: 'debug_clear', child: ListTile(leading: Icon(Icons.clear), title: Text('[Debug] Clear Override'))),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Logout'))),
      ],
      child: CircleAvatar(
        radius: 16,
        backgroundColor: AppColors.primary.withValues(alpha: 0.12),
        child: initial != null
            ? Text(initial, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700))
            : const Icon(Icons.person_outline, color: AppColors.primary),
      ),
    );
  }
}

// Dedicated header bar for Nurse dashboard
class _NurseHeaderBar extends StatelessWidget {
  final String title;
  final bool showMenu;
  const _NurseHeaderBar({required this.title, this.showMenu = false});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final veryNarrow = width < 420;
    final showBrand = !veryNarrow;
  final showBell = !veryNarrow;
  const showAssistant = true;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Menu',
                onPressed: () => Scaffold.maybeOf(ctx)?.openDrawer(),
                icon: const Icon(Icons.menu),
              ),
            ),
          if (showBrand) ...[
            Text('MedEquip', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primaryDark)),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.outline),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              veryNarrow ? title : 'Nurse • $title',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (showAssistant)
            IconButton(
              tooltip: 'AI Assistant',
              onPressed: () => Navigator.of(context).pushNamed('/assistant'),
              icon: const Icon(Icons.smart_toy_outlined),
            ),
          IconButton(
            tooltip: 'Knowledge Center',
            onPressed: () => Navigator.of(context).pushNamed('/knowledge'),
            icon: const Icon(Icons.menu_book_outlined),
          ),
          IconButton(
            tooltip: 'Equipment',
            onPressed: () => Navigator.of(context).pushNamed('/equipment'),
            icon: const Icon(Icons.precision_manufacturing_outlined),
          ),
          if (showBell) ...[
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open notifications (static)'))),
              icon: const Icon(Icons.notifications_none_outlined),
            ),
            const SizedBox(width: 4),
          ],
          const _ProfileMenu(),
        ],
      ),
    );
  }
}

// Dedicated side navigation for Nurse dashboard
class _NurseSideNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  const _NurseSideNav({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = const [
      _SideItem(Icons.dashboard_outlined, 'Overview'),
      _SideItem(Icons.build_outlined, 'Requests'),
      _SideItem(Icons.event_available_outlined, 'Maintenance'),
      _SideItem(Icons.history, 'History'),
      _SideItem(Icons.person_outline, 'Profile'),
      _SideItem(Icons.menu_book_outlined, 'Knowledge'),
      _SideItem(Icons.precision_manufacturing_outlined, 'Equipment'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: AppColors.outline)),
      ),
      child: ListView.builder(
        itemCount: items.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
              child: Text('Nurse', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
            );
          }
          final idx = i - 1;
          final it = items[idx];
          final selected = idx == currentIndex;
          return InkWell(
            onTap: () {
              if (it.label == 'Equipment') {
                Navigator.of(context).pushNamed('/equipment');
              } else if (it.label == 'Knowledge') {
                Navigator.of(context).pushNamed('/knowledge');
              } else if (it.label == 'Maintenance') {
                Navigator.of(context).pushNamed('/maintenance');
              } else {
                onSelect(idx);
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary.withValues(alpha: 0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(it.icon, color: selected ? AppColors.primary : AppColors.primaryDark),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      it.label,
                      style: GoogleFonts.sourceSans3(
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected ? AppColors.primary : AppColors.primaryDark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SideItem {
  final IconData icon;
  final String label;
  const _SideItem(this.icon, this.label);
}
