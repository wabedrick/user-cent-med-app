import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../auth/sign_in_screen.dart';
// Removed shared DashboardShell; using dedicated header + sidebar for Engineer
import '../repositories/repair_requests_repository.dart';
import '../models/repair_request_model.dart';
import '../repositories/user_repository.dart';
import '../repositories/equipment_repository.dart';
import '../widgets/error_utils.dart';

// Mock providers for engineer dashboard (later replace with Firestore queries)
final engineerWorkOrdersProvider = FutureProvider<List<EngineerWorkOrderSummary>>((ref) async {
  await Future.delayed(const Duration(milliseconds: 300));
  return [
    EngineerWorkOrderSummary('WO-4821', 'MRI Cooling System', 'Replace coolant filter', priority: Priority.high, progress: 0.2),
    EngineerWorkOrderSummary('WO-4822', 'Infusion Pump #14', 'Battery health check', priority: Priority.medium, progress: 0.65),
    EngineerWorkOrderSummary('WO-4823', 'Defibrillator #5', 'Firmware update pending', priority: Priority.low, progress: 0.0),
  ];
});

final engineerStatsProvider = FutureProvider<EngineerStats>((ref) async {
  await Future.delayed(const Duration(milliseconds: 220));
  return const EngineerStats(openOrders: 8, dueToday: 2, slaRisk: 1, completedThisWeek: 17);
});

enum Priority { low, medium, high }

class EngineerWorkOrderSummary {
  final String id;
  final String asset;
  final String title;
  final Priority priority;
  final double progress; // 0..1
  EngineerWorkOrderSummary(this.id, this.asset, this.title, {required this.priority, required this.progress});
}

class EngineerStats {
  final int openOrders;
  final int dueToday;
  final int slaRisk;
  final int completedThisWeek;
  const EngineerStats({required this.openOrders, required this.dueToday, required this.slaRisk, required this.completedThisWeek});
}

class EngineerDashboardScreen extends ConsumerStatefulWidget {
  const EngineerDashboardScreen({super.key});
  @override
  ConsumerState<EngineerDashboardScreen> createState() => _EngineerDashboardScreenState();
}

class _EngineerDashboardScreenState extends ConsumerState<EngineerDashboardScreen> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final titles = const ['Dashboard', 'Orders', 'History', 'Profile'];
    final title = titles[(tab >= 0 && tab < titles.length) ? tab : 0];
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 900;

    return Scaffold(
      drawer: isNarrow
          ? Drawer(
              child: SafeArea(
                child: _EngineerSideNav(
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
                child: _EngineerSideNav(
                  currentIndex: tab,
                  onSelect: (i) => setState(() => tab = i),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _EngineerHeaderBar(
                    title: title,
                    showMenu: isNarrow,
                  ),
                  const Divider(height: 1),
                  Expanded(child: _EngineerBody(tab: tab)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineerBody extends ConsumerWidget {
  final int tab;
  const _EngineerBody({required this.tab});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(engineerStatsProvider);
    final orders = ref.watch(engineerWorkOrdersProvider);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1100;

    Widget statsGrid() {
      return stats.when(
        data: (s) {
          final cards = [
            _StatCard(label: 'Open Orders', value: s.openOrders.toString(), icon: Icons.build_circle_outlined, color: AppColors.primary),
            _StatCard(label: 'Due Today', value: s.dueToday.toString(), icon: Icons.today_outlined, color: AppColors.warning),
            _StatCard(label: 'SLA Risk', value: s.slaRisk.toString(), icon: Icons.report_problem_outlined, color: AppColors.error),
            _StatCard(label: 'Completed (Week)', value: s.completedThisWeek.toString(), icon: Icons.task_alt, color: AppColors.success),
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
  error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(engineerStatsProvider)),
      );
    }

    Widget ordersList() {
      return orders.when(
        data: (list) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: list.isEmpty
              ? _EmptyState(
                  key: const ValueKey('empty'),
                  icon: Icons.verified_outlined,
                  title: 'No Active Work Orders',
                  message: 'All maintenance tasks are clear right now.',
                )
              : ListView.separated(
                  key: const ValueKey('list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) => _OrderTile(item: list[i]),
                ),
        ),
        loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator())),
  error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(engineerWorkOrdersProvider)),
      );
    }

    Widget dashboard() {
      final content = SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Operations Snapshot', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 18),
            statsGrid(),
            const SizedBox(height: 40),
            Row(
              children: [
                Text('Active Work Orders', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                TextButton.icon(onPressed: () => ref.invalidate(engineerWorkOrdersProvider), icon: const Icon(Icons.refresh), label: const Text('Refresh')),
              ],
            ),
            const SizedBox(height: 12),
            ordersList(),
            const SizedBox(height: 48),
            Text('Recent Technical Activity', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const _RecentEngineerActivity(),
            const SizedBox(height: 96),
          ],
        ),
      );
      if (isWide) {
        return Row(children: [Expanded(child: content), const SizedBox(width: 360, child: _EngineerRightPanel())]);
      }
      return content;
    }

    Widget placeholder(String title) => Center(child: Text('$title (static)', style: Theme.of(context).textTheme.titleLarge));
    switch (tab) {
      case 0:
        return dashboard();
      case 1:
        return const _EngineerOrdersTab();
      case 2:
        return placeholder('History');
      case 3:
        return placeholder('Profile');
      default:
        return dashboard();
    }
  }
}

class _EngineerOrdersTab extends ConsumerWidget {
  const _EngineerOrdersTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Not signed in'));

  // Use showFriendlyError for feedback
    final unassigned = ref.watch(openUnassignedRequestsProvider);
    final mine = ref.watch(assignedToMeRequestsProvider(user.uid));
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Open & Unassigned', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          unassigned.when(
            data: (list) => _RequestsList(
              list: list,
              emptyText: 'No unassigned requests',
              trailingBuilder: (req) => TextButton.icon(
                onPressed: () async {
                  try {
                    await ref.read(repairRequestsRepositoryProvider).assignToSelf(requestId: req.id, engineerId: user.uid);
                  } catch (e) {
                    if (context.mounted) {
                      showFriendlyError(context, e, fallback: 'Could not assign the request.');
                    }
                  }
                },
                icon: const Icon(Icons.how_to_reg),
                label: const Text('Assign to me'),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(openUnassignedRequestsProvider)),
          ),
          const SizedBox(height: 28),
          Text('Assigned to Me', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          mine.when(
            data: (list) => _RequestsList(
              list: list,
              emptyText: 'No active assignments',
              trailingBuilder: (req) => PopupMenuButton<String>(
                onSelected: (v) async {
                  try {
                    await ref.read(repairRequestsRepositoryProvider).updateStatus(requestId: req.id, status: v);
                  } catch (e) {
                    if (context.mounted) {
                      showFriendlyError(context, e, fallback: 'Could not update the request.');
                    }
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'in_progress', child: Text('In Progress')),
                  PopupMenuItem(value: 'resolved', child: Text('Resolved')),
                  PopupMenuItem(value: 'closed', child: Text('Closed')),
                ],
                child: const Icon(Icons.more_vert),
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorInline(message: friendlyMessageFor(e), onRetry: () => ref.invalidate(assignedToMeRequestsProvider(user.uid))),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _RequestsList extends StatelessWidget {
  final List<RepairRequest> list;
  final String emptyText;
  final Widget Function(RepairRequest) trailingBuilder;
  const _RequestsList({required this.list, required this.emptyText, required this.trailingBuilder});
  @override
  Widget build(BuildContext context) {
    if (list.isEmpty) {
      return _EmptyState(icon: Icons.task_alt, title: emptyText, message: '');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final r = list[i];
        return _EngineerRequestTile(request: r, trailing: trailingBuilder(r));
      },
    );
  }
}

class _EngineerRequestTile extends ConsumerWidget {
  final RepairRequest request;
  final Widget trailing;
  const _EngineerRequestTile({required this.request, required this.trailing});
  Color _statusColor() {
    switch (request.status) {
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
    final reporterAv = ref.watch(userByIdProvider(request.reportedByUserId));
    final reporter = reporterAv.maybeWhen(data: (u) => u?.displayName ?? u?.email ?? 'Unknown', orElse: () => '…');

    AsyncValue<String?> equipmentNameAv;
    if (request.equipmentId.isEmpty) {
      equipmentNameAv = const AsyncValue.data(null);
    } else {
      final eq = ref.watch(equipmentByIdProvider(request.equipmentId));
      equipmentNameAv = eq.whenData((e) => e?.name);
    }
    final equipmentName = equipmentNameAv.maybeWhen(data: (n) => n ?? 'Unknown equipment', orElse: () => '…');

    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: _statusColor().withValues(alpha: 0.12), child: Icon(Icons.build_outlined, color: _statusColor())),
        title: Text(request.description, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('Eq: $equipmentName • By: $reporter • Status: ${request.status}${request.assignedEngineerId != null ? ' • Assigned' : ''}'),
        trailing: trailing,
      ),
    );
  }
}

// Legacy header removed (DashboardShell provides header/search/actions)
// Dedicated header bar for Engineer dashboard
class _EngineerHeaderBar extends StatelessWidget {
  final String title;
  final bool showMenu;
  const _EngineerHeaderBar({required this.title, this.showMenu = false});
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
            Text(
              'MedEquip',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primaryDark),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.outline),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              veryNarrow ? title : 'Engineer • $title',
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
          const _EngineerProfileMenu(),
        ],
      ),
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
            Text(value, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 24, color: color)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  final EngineerWorkOrderSummary item;
  const _OrderTile({required this.item});
  Color _priorityColor() {
    switch (item.priority) {
      case Priority.low:
        return AppColors.mint;
      case Priority.medium:
        return AppColors.warning;
      case Priority.high:
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
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _priorityColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.build_outlined, color: _priorityColor()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.id, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(item.asset, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(item.title, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      backgroundColor: Colors.grey.withValues(alpha: 0.15),
                      value: item.progress,
                      valueColor: AlwaysStoppedAnimation<Color>(_priorityColor()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _priorityColor().withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(item.priority.name.toUpperCase(), style: GoogleFonts.sourceSans3(fontWeight: FontWeight.w600, fontSize: 11, color: _priorityColor())),
            ),
            const SizedBox(width: 4),
            IconButton(onPressed: () {}, icon: const Icon(Icons.chevron_right_rounded)),
          ],
        ),
      ),
    );
  }
}

class _RecentEngineerActivity extends StatelessWidget {
  const _RecentEngineerActivity();
  @override
  Widget build(BuildContext context) {
    final entries = List.generate(
      6,
      (i) => _ActivityEntry(
        icon: Icons.settings_suggest_outlined,
        title: 'WO-${4800 + i} status updated',
        time: '${i + 1}h ago',
        detail: i.isEven ? 'Technician started diagnostics' : 'Parts ordered',
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

class _EngineerRightPanel extends StatelessWidget {
  const _EngineerRightPanel();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(left: BorderSide(color: AppColors.outline)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(-2, 0))],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
        children: const [
          _PanelSection(title: 'Quick Actions', children: [
            _QuickAction(icon: Icons.add_circle_outline, label: 'New Work Order'),
            _QuickAction(icon: Icons.qr_code_scanner, label: 'Scan Asset'),
            _QuickAction(icon: Icons.inventory_2_outlined, label: 'Parts Catalogue'),
          ]),
          SizedBox(height: 32),
          _PanelSection(title: 'Reminders', children: [
            _ReminderChip(text: 'Replace MRI coolant filter'),
            _ReminderChip(text: 'Audit ventilators Friday'),
            _ReminderChip(text: 'Patch firmware (3 devices)'),
          ]),
        ],
      ),
    );
  }
}

// Legacy side nav removed (DashboardShell provides side navigation)
// Dedicated side navigation for Engineer dashboard
class _EngineerSideNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  const _EngineerSideNav({required this.currentIndex, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final items = const [
      _SideItem(Icons.dashboard_outlined, 'Dashboard'),
      _SideItem(Icons.list_alt_outlined, 'Orders'),
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
              child: Text('Engineer', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
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

// Reuse generic components from nurse dashboard - consider extracting to shared file later.
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

// Legacy _NavItem removed

class _EngineerProfileMenu extends ConsumerWidget {
  const _EngineerProfileMenu();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = FirebaseAuth.instance.currentUser?.email;
    final initial = (email != null && email.isNotEmpty) ? email.characters.first.toUpperCase() : null;
  return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        if (value == 'logout') {
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
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'))),
        PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Logout'))),
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
