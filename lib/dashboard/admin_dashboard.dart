// ignore_for_file: use_build_context_synchronously
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme.dart';
import 'user_dashboard.dart';
import 'engineer_dashboard.dart';
import '../repositories/equipment_repository.dart';
import '../models/equipment_model.dart';
import '../features/maintenance/maintenance_list_page.dart';
import '../repositories/user_repository.dart';
import '../providers/role_provider.dart';
import '../auth/unified_auth_gate.dart'; // updated gate
import '../widgets/error_utils.dart';
import '../repositories/role_requests_repository.dart';

// Toggle this to true only if you've deployed Cloud Functions with a callable
// `setUserRole`. Otherwise, role changes should be done via the offline script.
// Enable using the deployed callable Cloud Function `setUserRole` to sync
// both Firestore and custom claims atomically.
const bool kEnableRoleChangeViaFunctions = true;

final adminClaimProvider = FutureProvider<bool>((ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;
  try {
    final token = await user.getIdTokenResult(true);
    final role = (token.claims?['role'] as String?)?.toLowerCase();
    return role == 'admin';
  } catch (_) {
    return false;
  }
});

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int navIndex = 0;
  @override
  Widget build(BuildContext context) {
    final adminClaim = ref.watch(adminClaimProvider);
    final titles = const ['Overview', 'Equipment', 'Users', 'Audit'];
    final title = (navIndex >= 0 && navIndex < titles.length) ? titles[navIndex] : 'Overview';
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 900;

    return Scaffold(
      drawer: isNarrow
          ? Drawer(
              child: SafeArea(
                child: _AdminSideNav(
                  currentIndex: navIndex,
                  onSelect: (i) {
                    setState(() => navIndex = i);
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
                child: _AdminSideNav(
                  currentIndex: navIndex,
                  onSelect: (i) => setState(() => navIndex = i),
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _AdminHeaderBar(title: title, showMenu: isNarrow),
                  const Divider(height: 1),
                  Expanded(
                        child: adminClaim.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => FriendlyErrorView(error: e, title: 'Couldn’t verify access', onRetry: () => ref.refresh(adminClaimProvider)),
                          data: (isAdmin) => isAdmin ? _AdminBody(tab: navIndex) : const _AdminClaimMissing(),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminBody extends ConsumerWidget {
  final int tab;
  const _AdminBody({required this.tab});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (tab) {
      case 0:
        return const _AdminOverview();
      case 1:
        return const _AdminEquipmentTab();
      case 2:
        return const _UserRoleManager();
      case 3:
        return const _AuditLogsView();
      default:
        return const _AdminOverview();
    }
  }
}

class _AdminHeaderBar extends StatelessWidget {
  final String title;
  final bool showMenu;
  const _AdminHeaderBar({required this.title, this.showMenu = false});
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
  final veryNarrow = width < 420; // phones in portrait
  final medium = width < 820;

    // Decide which trailing widgets to show at each breakpoint
  final showBrand = !veryNarrow; // hide brand on very tight screens
  final showClaims = !medium; // show claims chip only on wide screens
  final showBell = !veryNarrow; // hide notifications bell on very tight screens
  const showAssistant = true; // always show AI Assistant button

    final headerRow = Row(
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
          // Title always expands to take the remaining space
          Expanded(
            child: Text(
              // Keep the label short on narrow widths to reduce overflow risk
              veryNarrow ? title : 'Admin • $title',
              style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (showClaims) const _ClaimsChip(),
          if (showClaims) const SizedBox(width: 8),
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
            _NotificationsButton(),
            const SizedBox(width: 4),
          ],
          const _AccountMenuButton(),
        ],
      );
    return Consumer(
      builder: (context, ref, _) {
        final diag = ref.watch(roleDiagnosticsProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.white,
              child: headerRow,
            ),
            diag.maybeWhen(
              data: (d) => d.mismatch ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                color: Colors.orange.shade700,
                child: Text('Role mismatch: claim=${d.claim ?? 'null'} firestore=${d.firestore ?? 'null'} effective=${d.effective ?? 'null'}',
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              ) : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

class _AdminSideNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  const _AdminSideNav({required this.currentIndex, required this.onSelect});
  @override
  Widget build(BuildContext context) {
    final items = const [
      _SideItem(Icons.dashboard_outlined, 'Overview'),
      _SideItem(Icons.precision_manufacturing_outlined, 'Equipment'),
      _SideItem(Icons.manage_accounts_outlined, 'Users'),
      _SideItem(Icons.receipt_long_outlined, 'Audit'),
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
              child: Text('Admin', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
            );
          }
          final idx = i - 1;
          final it = items[idx];
          final selected = idx == currentIndex;
          return InkWell(
            onTap: () => onSelect(idx),
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

class _AdminEquipmentTab extends ConsumerWidget {
  const _AdminEquipmentTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(equipmentListProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final addBtn = ElevatedButton.icon(
                onPressed: () async {
                  await showDialog(context: context, builder: (_) => const _EquipmentFormDialog());
                },
                icon: const Icon(Icons.add),
                label: Text(compact ? 'Add' : 'Add Equipment'),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Equipment Management', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    addBtn,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: Text('Equipment Management', style: Theme.of(context).textTheme.titleLarge)),
                  addBtn,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: list.when(
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(child: Text('No equipment yet'));
                  }
                  return LayoutBuilder(builder: (ctx, box) {
                    return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final e = items[i];
                      return ListTile(
                        leading: const Icon(Icons.precision_manufacturing_outlined),
                        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${e.manufacturer} • ${e.model}', maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit',
                                onPressed: () async {
                                  await showDialog(context: context, builder: (_) => _EquipmentFormDialog(equipment: e));
                                },
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Delete',
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Delete equipment?'),
                                      content: Text('This will delete "${e.name}" and cannot be undone.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                                        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                           try {
                                      await ref.read(equipmentRepositoryProvider).delete(e.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                                      }
                                    } catch (e) {
                                             if (context.mounted) {
                                               showFriendlyError(context, e, fallback: 'Could not delete item.');
                                             }
                                    }
                                  }
                                },
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                  });
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: FriendlyErrorView(error: e, title: 'Couldn’t load data', onRetry: () => ref.invalidate(equipmentListProvider))),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EquipmentFormDialog extends ConsumerStatefulWidget {
  final Equipment? equipment;
  const _EquipmentFormDialog({this.equipment});
  @override
  ConsumerState<_EquipmentFormDialog> createState() => _EquipmentFormDialogState();
}

class _EquipmentFormDialogState extends ConsumerState<_EquipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _model;
  late final TextEditingController _manufacturer;
  late final TextEditingController _manual;
  late final TextEditingController _video;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.equipment;
    _name = TextEditingController(text: e?.name ?? '');
    _model = TextEditingController(text: e?.model ?? '');
    _manufacturer = TextEditingController(text: e?.manufacturer ?? '');
    _manual = TextEditingController(text: e?.manualPdfUrl ?? '');
    _video = TextEditingController(text: e?.videoTutorialUrl ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _manufacturer.dispose();
    _manual.dispose();
    _video.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.equipment != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Equipment' : 'Add Equipment'),
      scrollable: true,
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 8,
      content: LayoutBuilder(
        builder: (ctx, constraints) {
          final screenW = MediaQuery.of(ctx).size.width;
          final dialogW = screenW > 560 ? 520.0 : (screenW - 40).clamp(280.0, 520.0).toDouble();
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: dialogW),
            child: SizedBox(
              width: dialogW,
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.disabled,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Name *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _manufacturer,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Manufacturer'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _model,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Model'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _manual,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Manual PDF URL'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _video,
                      decoration: const InputDecoration(labelText: 'Video Tutorial URL'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() => _saving = true);
                  final repo = ref.read(equipmentRepositoryProvider);
                  try {
                    if (isEdit) {
                      final e0 = widget.equipment!;
                      final updated = Equipment(
                        id: e0.id,
                        name: _name.text.trim(),
                        model: _model.text.trim(),
                        manufacturer: _manufacturer.text.trim(),
                        manualPdfUrl: _manual.text.trim(),
                        videoTutorialUrl: _video.text.trim(),
                      );
                      await repo.update(updated);
                    } else {
                      final newE = Equipment(
                        id: '',
                        name: _name.text.trim(),
                        model: _model.text.trim(),
                        manufacturer: _manufacturer.text.trim(),
                        manualPdfUrl: _manual.text.trim(),
                        videoTutorialUrl: _video.text.trim(),
                      );
                      await repo.create(newE);
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Updated' : 'Created')));
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showFriendlyError(context, e, fallback: 'Could not save. Please try again.');
                    }
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

class _AdminClaimMissing extends ConsumerWidget {
  const _AdminClaimMissing();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Admin access not active yet', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const SizedBox(
                width: 500,
                child: Text(
                  'Your account may have been promoted to admin recently. Refresh your ID token or sign out/in.',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.currentUser?.getIdToken(true);
                      ref.invalidate(adminClaimProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                  TextButton(
                    onPressed: () async { await FirebaseAuth.instance.signOut(); },
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminOverview extends ConsumerWidget {
  const _AdminOverview();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        const gap = 16.0;
        // Choose 1 or 2 columns for larger sections
        final twoCols = maxW >= 940;
        final colW = twoCols ? (maxW - gap) / 2 : maxW;
        final kpiW = twoCols ? (maxW - (gap * 3)) / 4 : (maxW - gap) / 2;
  final smallW = twoCols ? 360.0 : maxW; // preview cards width; full width on narrow

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _OverviewToolbar(),
                const SizedBox(height: gap),
                // KPIs
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(width: kpiW, child: _KpiCard(title: 'Total Equipment', value: '124', icon: Icons.precision_manufacturing_outlined, color: AppColors.primary)),
                    SizedBox(width: kpiW, child: _KpiCard(title: 'Available', value: '92', icon: Icons.check_circle_outline, color: Colors.teal)),
                    SizedBox(width: kpiW, child: _KpiCard(title: 'In Maintenance', value: '18', icon: Icons.build_circle_outlined, color: Colors.orange)),
                    SizedBox(width: kpiW, child: _KpiCard(title: 'Out of Service', value: '14', icon: Icons.error_outline, color: Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: gap),

                // Maintenance + Work Orders
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: colW,
                      child: _SectionCard(
                        title: 'Upcoming Maintenance',
                        trailing: _ViewAllButton(onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const MaintenanceListPage()),
                          );
                        }),
                        child: const _UpcomingMaintenanceList(),
                      ),
                    ),
                    SizedBox(
                      width: colW,
                      child: _SectionCard(
                        title: 'Work Orders Summary',
                        trailing: _ViewAllButton(onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const WorkOrdersPage()),
                          );
                        }),
                        child: const _WorkOrdersSummary(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: gap),

                // Inventory + Distribution
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: colW,
                      child: _SectionCard(
                        title: 'Inventory (Spare Parts)',
                        trailing: _ViewAllButton(onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const InventoryPage()),
                          );
                        }),
                        child: const _InventorySummary(),
                      ),
                    ),
                    SizedBox(
                      width: colW,
                      child: _SectionCard(
                        title: 'Equipment Distribution',
                        trailing: _ViewAllButton(onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DistributionPage()),
                          );
                        }),
                        child: const _EquipmentDistribution(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: gap),

                // System + Compliance
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(
                      width: colW,
                      child: const _SectionCard(
                        title: 'System Health',
                        child: _SystemHealth(),
                      ),
                    ),
                    SizedBox(
                      width: colW,
                      child: _SectionCard(
                        title: 'Compliance Deadlines',
                        trailing: _ViewAllButton(onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const CompliancePage()),
                          );
                        }),
                        child: const _ComplianceDeadlines(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: gap),

                // Notifications + Audit + Users (small blocks -> adaptive widths)
                Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    SizedBox(width: smallW, child: _SectionCard(title: 'Recent Notifications', trailing: _ViewAllButton(onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsPage())); }), child: const _NotificationsPreview())),
                    SizedBox(width: smallW, child: _SectionCard(title: 'Audit Summary', trailing: _ViewAllButton(onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuditPage())); }), child: const _AuditSummaryStatic())),
                    SizedBox(width: smallW, child: _SectionCard(title: 'Users Snapshot', trailing: _ViewAllButton(onPressed: () { Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UsersSnapshotPage())); }), child: const _UsersSnapshot())),
                    SizedBox(
                      width: smallW,
                      child: const _SectionCard(
                        title: 'Open other dashboards',
                        child: _RoleDashboardsLinks(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoleDashboardsLinks extends StatelessWidget {
  const _RoleDashboardsLinks();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.medical_services_outlined),
          title: const Text('User dashboard'),
          subtitle: const Text('View the general user workspace'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const UserDashboardScreen()),
            );
          },
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.engineering_outlined),
          title: const Text('Engineer dashboard'),
          subtitle: const Text('View the engineer workspace'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EngineerDashboardScreen()),
            );
          },
        ),
      ],
    );
  }
}

class _OverviewToolbar extends StatefulWidget {
  const _OverviewToolbar();
  @override
  State<_OverviewToolbar> createState() => _OverviewToolbarState();
}

class _OverviewToolbarState extends State<_OverviewToolbar> {
  String _range = 'Last 30 days';
  final List<String> _ranges = const ['Last 7 days', 'Last 30 days', 'Last 90 days'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final veryTight = maxW < 360;
        final compact = maxW < 520;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: compact ? 8 : 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: math.min(220, maxW)),
                  child: DropdownButtonFormField<String>(
                    initialValue: _range,
                    decoration: const InputDecoration(
                      labelText: 'Date range',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: _ranges
                        .map((r) => DropdownMenuItem<String>(
                              value: r,
                              child: Text(r, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _range = v ?? _range),
                  ),
                ),
                if (!veryTight) const SizedBox(width: 4),
                if (veryTight) ...[
                  // Icon-only actions on very tight widths
                  IconButton(
                    tooltip: 'Add Equipment',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Add equipment (static)')),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  IconButton(
                    tooltip: 'New Work Order',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('New work order (static)')),
                      );
                    },
                    icon: const Icon(Icons.assignment_outlined),
                  ),
                  IconButton(
                    tooltip: 'Export',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Export $_range (static)')),
                      );
                    },
                    icon: const Icon(Icons.download_outlined),
                  ),
                ] else ...[
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Add equipment (static)')),
                      );
                    },
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(compact ? 'Add' : 'Add Equipment'),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('New work order (static)')),
                      );
                    },
                    icon: const Icon(Icons.assignment_outlined),
                    label: Text(compact ? 'Work Order' : 'New Work Order'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Export $_range (static)')),
                      );
                    },
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}



class WorkOrdersPage extends StatelessWidget {
  const WorkOrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final workOrders = const [
      ('WO-234', 'Ventilator ICU-1', 'High', 'Open'),
      ('WO-235', 'Infusion Pump Ward-3', 'Medium', 'In Progress'),
      ('WO-236', 'Defibrillator ER', 'Low', 'Closed'),
      ('WO-237', 'Anesthesia Machine OR-2', 'High', 'Overdue'),
    ];
    Color st(String s) =>
        s == 'Open' ? Colors.orange : s == 'In Progress' ? Colors.blue : s == 'Overdue' ? Colors.redAccent : Colors.teal;
    return Scaffold(
      appBar: AppBar(title: const Text('Work Orders')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: ListView.separated(
            itemCount: workOrders.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final w = workOrders[i];
              return ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Text('${w.$1} • ${w.$2}'),
                subtitle: Text('Priority ${w.$3}'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: st(w.$4).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(w.$4, style: TextStyle(color: st(w.$4), fontWeight: FontWeight.w600)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory • Spare Parts')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: _InventorySummary(),
      ),
    );
  }
}

class DistributionPage extends StatelessWidget {
  const DistributionPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Equipment Distribution')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: _EquipmentDistribution(),
      ),
    );
  }
}

class CompliancePage extends StatelessWidget {
  const CompliancePage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compliance Deadlines')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: _ComplianceDeadlines(),
      ),
    );
  }
}

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: const Padding(
        padding: EdgeInsets.all(16),
        child: _NotificationsPreview(),
      ),
    );
  }
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext context) {
    final logs = const [
      ('2025-09-12 08:34', 'USER_ROLE_UPDATE', 'admin@clinic.com', 'alex@clinic.com', 'role engineer -> admin'),
      ('2025-09-11 17:12', 'DEVICE_STATUS_CHANGE', 'sam@nurse.com', 'Ventilator-ICU-1', 'status down -> maintenance'),
      ('2025-09-10 09:05', 'LOGIN', 'jane@admin.com', '-', 'successful login'),
      ('2025-09-08 14:28', 'WORK_ORDER_CREATE', 'alex@clinic.com', 'WO-234', 'priority high'),
      ('2025-09-07 10:12', 'USER_CREATE', 'system', 'paul@clinic.com', 'new engineer'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Audit Logs')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final l = logs[i];
              return ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: Text(l.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('by ${l.$3} • target ${l.$4} • ${l.$5}', maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: SizedBox(width: 120, child: Text(l.$1, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              );
            },
          ),
        ),
      ),
    );
  }
}

class UsersSnapshotPage extends StatelessWidget {
  const UsersSnapshotPage({super.key});
  @override
  Widget build(BuildContext context) {
    final users = const [
      ('jane@admin.com', 'admin'),
      ('alex@clinic.com', 'engineer'),
      ('sam@nurse.com', 'nurse'),
      ('paul@clinic.com', 'engineer'),
      ('dana@nurse.com', 'nurse'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) => ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(users[i].$1),
              subtitle: Text('Role: ${users[i].$2}'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewAllButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _ViewAllButton({required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.open_in_new, size: 16),
      label: const Text('View all'),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const _SectionCard({required this.title, required this.child, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null)
                  Flexible(
                    flex: 0,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: trailing!,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _KpiCard({required this.title, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color)),
                  const SizedBox(height: 2),
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpcomingMaintenanceList extends StatelessWidget {
  const _UpcomingMaintenanceList();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('Oct 02', 'Anesthesia Machine', 'OR-2', 'High'),
      ('Oct 05', 'Infusion Pump', 'Ward-3', 'Medium'),
      ('Oct 08', 'Ventilator', 'ICU-1', 'High'),
      ('Oct 12', 'Defibrillator', 'ER', 'Low'),
    ];
    Color priorityColor(String p) {
      switch (p) {
        case 'High':
          return Colors.redAccent;
        case 'Medium':
          return Colors.orange;
        default:
          return Colors.teal;
      }
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final (date, name, loc, pr) = items[i];
        return ListTile(
          leading: CircleAvatar(backgroundColor: AppColors.primary.withValues(alpha: 0.12), child: const Icon(Icons.build_outlined, color: AppColors.primary)),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('$loc • Due $date'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: priorityColor(pr).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
            child: Text(pr, style: TextStyle(color: priorityColor(pr), fontWeight: FontWeight.w600)),
          ),
        );
      },
    );
  }
}

class _WorkOrdersSummary extends StatelessWidget {
  const _WorkOrdersSummary();
  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Open', 12, Colors.orange),
      ('In Progress', 5, Colors.blue),
      ('Overdue', 3, Colors.redAccent),
      ('Closed (30d)', 41, Colors.teal),
    ];
    return Column(
      children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: r.$3, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(r.$1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: r.$3.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text('${r.$2}', style: TextStyle(color: r.$3, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        const Align(alignment: Alignment.centerLeft, child: Text('Completion progress')),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: 0.68, minHeight: 10, color: AppColors.primary, backgroundColor: AppColors.primary.withValues(alpha: 0.12)),
        ),
      ],
    );
  }
}

class _InventorySummary extends StatelessWidget {
  const _InventorySummary();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('O2 Sensor', 6, 40),
      ('Syringe 50ml', 22, 55),
      ('ECG Leads', 8, 20),
      ('Battery Pack', 3, 12),
    ];
    Color barColor(int pct) => pct < 25 ? Colors.redAccent : (pct < 50 ? Colors.orange : Colors.teal);

    return Column(
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Text('Qty ${it.$2}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: it.$3 / 100.0, minHeight: 10, color: barColor(it.$3), backgroundColor: barColor(it.$3).withValues(alpha: 0.12)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EquipmentDistribution extends StatelessWidget {
  const _EquipmentDistribution();
  @override
  Widget build(BuildContext context) {
    final depts = [
      ('ICU', 34, Colors.indigo),
      ('ER', 22, Colors.redAccent),
      ('OR', 18, Colors.teal),
      ('Wards', 26, Colors.orange),
    ];
    return Column(
      children: [
        for (final d in depts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: d.$3, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(d.$1)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(value: d.$2 / 100.0, minHeight: 10, color: d.$3, backgroundColor: d.$3.withValues(alpha: 0.12)),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${d.$2}%'),
              ],
            ),
          ),
      ],
    );
  }
}

class _SystemHealth extends StatelessWidget {
  const _SystemHealth();
  @override
  Widget build(BuildContext context) {
    final services = [
      ('Auth', true),
      ('Firestore', true),
      ('Storage', true),
      ('Messaging', true),
    ];
    return Column(
      children: [
        for (final s in services)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(s.$2 ? Icons.check_circle_outline : Icons.error_outline, color: s.$2 ? Colors.teal : Colors.redAccent),
            title: Text(s.$1),
            subtitle: Text(s.$2 ? 'Operational' : 'Issue detected'),
          ),
      ],
    );
  }
}

class _ComplianceDeadlines extends StatelessWidget {
  const _ComplianceDeadlines();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('ISO 13485 audit', 'Oct 20', 'Pending'),
      ('Electrical Safety checks', 'Oct 28', 'Scheduled'),
      ('Calibration batch #42', 'Nov 05', 'Pending'),
    ];
    Color badgeColor(String s) => s == 'Pending' ? Colors.orange : Colors.teal;
    return Column(
      children: [
        for (final it in items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.rule_folder_outlined, color: AppColors.primary),
            title: Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('Due ${it.$2}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: badgeColor(it.$3).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
              child: Text(it.$3, style: TextStyle(color: badgeColor(it.$3), fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}

class _NotificationsPreview extends StatelessWidget {
  const _NotificationsPreview();
  @override
  Widget build(BuildContext context) {
    final notifs = [
      ('Work order WO-234 assigned to you', '2h ago'),
      ('Battery pack stock low (<5)', '1d ago'),
      ('New engineer added: alex@clinic.com', '3d ago'),
    ];
    return Column(
      children: [
        for (final n in notifs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notifications_none_outlined),
            title: Text(n.$1, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: Text(n.$2, style: const TextStyle(color: Colors.black54)),
          ),
      ],
    );
  }
}

class _AuditSummaryStatic extends StatelessWidget {
  const _AuditSummaryStatic();
  @override
  Widget build(BuildContext context) {
    final items = [
      ('Events (7d)', 128, AppColors.primary),
      ('Role changes', 3, Colors.orange),
      ('Denied attempts', 2, Colors.redAccent),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: it.$3, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(it.$1)),
                Text('${it.$2}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
      ],
    );
  }
}

class _UsersSnapshot extends StatelessWidget {
  const _UsersSnapshot();
  @override
  Widget build(BuildContext context) {
    final users = [
      ('Admins', 4, Colors.indigo),
      ('Engineers', 12, Colors.teal),
      ('Nurses', 38, Colors.orange),
    ];
    return Column(
      children: [
        for (final u in users)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: u.$3, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(u.$1)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: u.$3.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text('${u.$2}', style: TextStyle(color: u.$3, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// Legacy _Header removed (header now provided by DashboardShell)

// _HeaderSearch removed (now provided by DashboardShell)

class _NotificationsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Simple bell with a red dot to imply unread notifications
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Open notifications (static)')),
              );
            },
            icon: const Icon(Icons.notifications_none_outlined),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
    );
  }
}
// _HeaderOverflowMenu removed (now provided by DashboardShell)

class _AccountMenuButton extends StatelessWidget {
  const _AccountMenuButton();
  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email;
    final initial = (email != null && email.isNotEmpty) ? email.characters.first.toUpperCase() : null;
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (value) async {
        if (value == 'signout') {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
          String? err;
          try {
            // Force token refresh cancellation-safe; signOut clears listeners -> AuthGate rebuilds.
            await FirebaseAuth.instance.signOut();
          } catch (e) {
            err = e.toString();
          }
          if (!context.mounted) return;
          // Remove the progress dialog
          navigator.pop();
          if (err != null) {
            showFriendlyError(context, err, fallback: 'Sign out failed. Please try again.');
            return;
          }
          // Clear entire stack & ensure we land on AuthGate (main.dart home)
          navigator.pushAndRemoveUntil(
            PageRouteBuilder(pageBuilder: (_, __, ___) => const UnifiedAuthGate(), transitionDuration: Duration.zero),
            (route) => false,
          );
          // Post-frame show confirmation (AuthGate context may differ, so schedule)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            messenger.showSnackBar(const SnackBar(content: Text('Signed out')));
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$value (static)')),
          );
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'profile', child: ListTile(leading: Icon(Icons.person_outline), title: Text('Profile'))),
        PopupMenuItem(value: 'settings', child: ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'signout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'))),
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

class _ClaimsChip extends StatefulWidget {
  const _ClaimsChip();
  @override
  State<_ClaimsChip> createState() => _ClaimsChipState();
}

class _ClaimsChipState extends State<_ClaimsChip> {
  String _fullLabel = 'Fetching…';
  String _shortLabel = 'Fetching…';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _fullLabel = 'Signed out';
          _shortLabel = 'Signed out';
        });
      } else {
        final tok = await user.getIdTokenResult(true);
        final role = (tok.claims?['role'] as String?) ?? 'unknown';
        final emailOrUid = user.email ?? user.uid;
        setState(() {
          _fullLabel = '$emailOrUid • $role';
          _shortLabel = role; // keep chip compact to avoid overflow
        });
      }
    } catch (_) {
      setState(() {
        _fullLabel = 'Claims unavailable';
        _shortLabel = 'unknown';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: _fullLabel,
      child: InputChip(
        avatar: _loading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.verified_user_outlined, size: 18),
        label: Text(_shortLabel, overflow: TextOverflow.ellipsis),
        onPressed: _refresh,
      ),
    );
  }
}

// _AdminSideNav removed (now provided by DashboardShell)

class _AuditLogsView extends ConsumerWidget {
  const _AuditLogsView();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = FirebaseFirestore.instance
        .collection('audit_logs')
        .orderBy('ts', descending: true)
        .limit(200)
        .snapshots();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Failed to load: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? const [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Audit Logs', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: docs.isEmpty
                    ? const Center(child: Text('No audit logs'))
                    : ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final d = docs[i].data();
                          final type = (d['type'] ?? '').toString();
                          final target = (d['targetUid'] ?? d['target'] ?? '-').toString();
                          final changedBy = (d['changedBy'] ?? d['by'] ?? '-').toString();
                          final ts = d['ts'];
                          String when = '';
                          try { when = (ts as dynamic).toDate().toString().split('.').first; } catch (_) {}
                          String subtitle = 'by $changedBy • target $target';
                          if (d['newRole'] != null) subtitle += ' • role ${d['newRole']}';
                          return ListTile(
                            leading: const Icon(Icons.event_note_outlined),
                            title: Text(type, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: SizedBox(width: 150, child: Text(when, textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: Colors.black54))),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UserRoleManager extends StatelessWidget {
  const _UserRoleManager();
  @override
  Widget build(BuildContext context) {
    return const _LiveUserRoleManager();
  }
}

class _LiveUserRoleManager extends ConsumerStatefulWidget {
  const _LiveUserRoleManager();
  @override
  ConsumerState<_LiveUserRoleManager> createState() => _LiveUserRoleManagerState();
}

class _LiveUserRoleManagerState extends ConsumerState<_LiveUserRoleManager> {
  String _filter = '';
  bool _showOnlyAdmins = false;
  bool _showOnlyEngineers = false;
  bool _showOnlyNurses = false;
  bool _includeSelf = true;
  bool _calling = false;

  final _roles = const ['admin','engineer','nurse'];

  @override
  Widget build(BuildContext context) {
    final asyncUsers = ref.watch(usersListProvider);
    final pending = ref.watch(pendingRoleRequestsProvider);
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pending role requests banner/card
        pending.when(
          loading: () => const LinearProgressIndicator(minHeight: 2),
          error: (e, _) => const SizedBox.shrink(),
          data: (list) {
            if (list.isEmpty) return const SizedBox.shrink();
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pending_actions, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text('Pending role requests (${list.length})', style: Theme.of(context).textTheme.titleMedium),
                        const Spacer(),
                        IconButton(tooltip: 'Refresh', onPressed: () => ref.invalidate(pendingRoleRequestsProvider), icon: const Icon(Icons.refresh)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = list[i];
                        final uid = (r['uid'] ?? r['id'] ?? '').toString();
                        final email = (r['email'] ?? '').toString();
                        final name = (r['displayName'] ?? '').toString();
                        final reqRole = (r['requestedRole'] ?? 'engineer').toString();
                        return ListTile(
                          leading: const Icon(Icons.how_to_reg_outlined),
                          title: Text(email.isNotEmpty ? email : uid, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(name.isNotEmpty ? '$name • $reqRole' : reqRole),
                          trailing: Wrap(spacing: 8, children: [
                            OutlinedButton(
                              onPressed: () async {
                                try {
                                  // Approve: set role to requestedRole, then mark approved
                                  final repo = ref.read(userRepositoryProvider);
                                  await repo.updateUserRole(uid: uid, newRole: reqRole, callFunction: kEnableRoleChangeViaFunctions);
                                  await ref.read(roleRequestsRepositoryProvider).markApproved(uid: uid, adminUid: currentUid ?? '');
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Approved $uid as $reqRole')));
                                  }
                                } catch (e) {
                                  if (context.mounted) showFriendlyError(context, e, fallback: 'Approve failed');
                                }
                              },
                              child: const Text('Approve'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final reason = await showDialog<String>(
                                  context: context,
                                  builder: (dCtx) {
                                    final ctrl = TextEditingController();
                                    return AlertDialog(
                                      title: const Text('Deny request'),
                                      content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Reason (optional)')),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(dCtx).pop(), child: const Text('Cancel')),
                                        FilledButton(onPressed: () => Navigator.of(dCtx).pop(ctrl.text.trim()), child: const Text('Deny')),
                                      ],
                                    );
                                  },
                                );
                                try {
                                  await ref.read(roleRequestsRepositoryProvider).markDenied(uid: uid, adminUid: currentUid ?? '', reason: (reason?.isEmpty ?? true) ? null : reason);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Denied request for $uid')));
                                  }
                                } catch (e) {
                                  if (context.mounted) showFriendlyError(context, e, fallback: 'Deny failed');
                                }
                              },
                              child: const Text('Deny'),
                            ),
                          ]),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Row(
          children: [
            Expanded(child: Text('User Role Management', style: Theme.of(context).textTheme.titleLarge)),
            IconButton(
              tooltip: 'Refresh list',
              onPressed: () => ref.invalidate(usersListProvider),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search email / name', isDense: true, border: OutlineInputBorder()),
                onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              ),
            ),
            FilterChip(
              label: const Text('Admins'),
              selected: _showOnlyAdmins,
              onSelected: (v) => setState(() { _showOnlyAdmins = v; if (v) { _showOnlyEngineers=false; _showOnlyNurses=false; } }),
            ),
            FilterChip(
              label: const Text('Engineers'),
              selected: _showOnlyEngineers,
              onSelected: (v) => setState(() { _showOnlyEngineers = v; if (v) { _showOnlyAdmins=false; _showOnlyNurses=false; } }),
            ),
            FilterChip(
              label: const Text('Nurses'),
              selected: _showOnlyNurses,
              onSelected: (v) => setState(() { _showOnlyNurses = v; if (v) { _showOnlyAdmins=false; _showOnlyEngineers=false; } }),
            ),
            FilterChip(
              label: const Text('Include me'),
              selected: _includeSelf,
              onSelected: (v) => setState(() => _includeSelf = v),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: asyncUsers.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => FriendlyErrorView(error: e, title: 'Couldn’t load users', onRetry: () => ref.invalidate(usersListProvider)),
            data: (users) {
              var list = users;
              if (_filter.isNotEmpty) {
                list = list.where((u) => u.email.toLowerCase().contains(_filter) || u.displayName.toLowerCase().contains(_filter)).toList();
              }
              if (!_includeSelf && currentUid != null) {
                list = list.where((u) => u.uid != currentUid).toList();
              }
              if (_showOnlyAdmins) list = list.where((u) => u.role == 'admin').toList();
              if (_showOnlyEngineers) list = list.where((u) => u.role == 'engineer').toList();
              if (_showOnlyNurses) list = list.where((u) => u.role == 'nurse').toList();
              list.sort((a,b) => a.email.compareTo(b.email));
              final adminCount = users.where((u) => u.role == 'admin').length;
              return Card(
                clipBehavior: Clip.antiAlias,
                child: list.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No users'))) : ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final u = list[i];
                    final isSelf = u.uid == currentUid;
                    final canChange = !_calling; // disabled while calling
                    return ListTile(
                      leading: CircleAvatar(child: Text(u.email.isNotEmpty ? u.email[0].toUpperCase() : '?')),
                      title: Text(u.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(u.displayName.isNotEmpty ? '${u.displayName} • ${u.role}' : u.role),
                      trailing: SizedBox(
                        width: 200,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _roles.contains(u.role) ? u.role : null,
                                items: _roles.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                                onChanged: !canChange ? null : (val) async {
                                  if (val == null || val == u.role) return;
                                  // Safeguard: do not allow removing last admin
                                  if (u.role == 'admin' && val != 'admin' && adminCount <= 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot demote the last admin')));
                                    return;
                                  }
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (dCtx) => AlertDialog(
                                      title: const Text('Confirm role change'),
                                      content: Text('Change role for ${u.email} to "$val"?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(dCtx).pop(false), child: const Text('Cancel')),
                                        FilledButton(onPressed: () => Navigator.of(dCtx).pop(true), child: const Text('Change')),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  setState(() => _calling = true);
                                  try {
                                    final repo = ref.read(userRepositoryProvider);
                                    await repo.updateUserRole(uid: u.uid, newRole: val, callFunction: kEnableRoleChangeViaFunctions);
                                    if (isSelf) {
                                      await FirebaseAuth.instance.currentUser?.getIdToken(true);
                                      forceRoleReload(ref);
                                      ref.invalidate(adminClaimProvider);
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role updated')));
                                  } catch (e) {
                                    showFriendlyError(context, e, fallback: 'Could not update role.');
                                  } finally {
                                    if (mounted) setState(() => _calling = false);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text('Notes: Role changes update Firestore immediately. ${kEnableRoleChangeViaFunctions ? 'Custom claims are also synced via Cloud Function.' : 'Deploy the callable setUserRole Cloud Function and set kEnableRoleChangeViaFunctions=true to sync custom claims automatically.'}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}
