import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../theme.dart';

class NavItemData {
  final IconData icon;
  final String label;
  const NavItemData(this.icon, this.label);
}

class DashboardShell extends StatelessWidget {
  final String brandName;
  final String pageTitle;
  final List<NavItemData> navItems;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget body;
  final List<Widget> actions;
  final bool showSearch;
  final double sideWidth;

  const DashboardShell({
    super.key,
    required this.brandName,
    required this.pageTitle,
    required this.navItems,
    required this.selectedIndex,
    required this.onSelect,
    required this.body,
    this.actions = const [],
    this.showSearch = true,
    this.sideWidth = 78,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _SideNav(
            brandName: brandName,
            items: navItems,
            selectedIndex: selectedIndex,
            onSelect: onSelect,
            width: sideWidth,
          ),
          Expanded(
            child: Column(
              children: [
                SafeArea(
                  top: true,
                  bottom: false,
                  child: _Header(
                    brandName: brandName,
                    pageTitle: pageTitle,
                    actions: actions,
                    showSearch: showSearch,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: body,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String brandName;
  final String pageTitle;
  final List<Widget> actions;
  final bool showSearch;
  const _Header({required this.brandName, required this.pageTitle, required this.actions, required this.showSearch});
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final veryNarrow = constraints.maxWidth < 420;
        final medium = constraints.maxWidth < 900;
        return Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.outline)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_moon_outlined, size: 24, color: AppColors.primary),
              const SizedBox(width: 8),
              if (!veryNarrow) ...[
                Text(brandName, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: AppColors.outline),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(pageTitle, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (showSearch && !medium) ...[
                const SizedBox(width: 8),
                SizedBox(width: math.min(320, constraints.maxWidth * 0.3), child: _HeaderSearch()),
              ],
              const SizedBox(width: 8),
              if (veryNarrow)
                const _HeaderOverflowMenu()
              else
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeaderSearch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search equipment, orders, users…',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      ),
      onSubmitted: (q) {
        if (q.trim().isEmpty) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search "$q" (static)')),
        );
      },
    );
  }
}

class _HeaderOverflowMenu extends StatelessWidget {
  const _HeaderOverflowMenu();
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Menu',
      icon: const Icon(Icons.more_vert),
      onSelected: (value) async {
        switch (value) {
          case 'notifications':
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Open notifications (static)')));
            break;
          case 'help':
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Help is not available in this static build.')));
            break;
          case 'signout':
            await FirebaseAuth.instance.signOut();
            if (context.mounted) {
              Navigator.of(context).popUntil((r) => r.isFirst);
            }
            break;
        }
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(value: 'notifications', child: ListTile(leading: Icon(Icons.notifications_none_outlined), title: Text('Notifications'))),
        PopupMenuItem(value: 'help', child: ListTile(leading: Icon(Icons.help_outline), title: Text('Help'))),
        PopupMenuDivider(),
        PopupMenuItem(value: 'signout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'))),
      ],
    );
  }
}

class _SideNav extends StatelessWidget {
  final String brandName;
  final List<NavItemData> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final double width;
  const _SideNav({required this.brandName, required this.items, required this.selectedIndex, required this.onSelect, required this.width});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(right: BorderSide(color: AppColors.outline)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(2, 0)),
        ],
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            const Icon(Icons.shield_moon_outlined, size: 28, color: AppColors.primary),
            const SizedBox(height: 14),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final active = i == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Tooltip(
                      message: items[i].label,
                      waitDuration: const Duration(milliseconds: 600),
                      child: InkWell(
                        onTap: () => onSelect(i),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: active ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Icon(items[i].icon, color: active ? AppColors.primary : AppColors.primaryLight),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Tooltip(
              message: 'Settings',
              child: IconButton(
                tooltip: 'Settings',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings (static)'))),
                icon: const Icon(Icons.settings_outlined, color: AppColors.primaryLight),
              ),
            ),
            Tooltip(
              message: 'Sign out',
              child: IconButton(
                tooltip: 'Sign out',
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
                icon: const Icon(Icons.logout, color: AppColors.primaryLight),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
