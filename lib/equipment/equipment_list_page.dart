import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/equipment_repository.dart';
import 'equipment_detail_page.dart';
import '../widgets/error_utils.dart';

class EquipmentListPage extends ConsumerStatefulWidget {
  const EquipmentListPage({super.key});
  @override
  ConsumerState<EquipmentListPage> createState() => _EquipmentListPageState();
}

class _EquipmentListPageState extends ConsumerState<EquipmentListPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(equipmentListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Equipment Catalogue')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search equipment', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: list.when(
              data: (items) {
                final filtered = _query.isEmpty
                    ? items
                    : items.where((e) => e.name.toLowerCase().contains(_query) || e.model.toLowerCase().contains(_query) || e.manufacturer.toLowerCase().contains(_query)).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No equipment found'));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final e = filtered[i];
                    return ListTile(
                      leading: const Icon(Icons.precision_manufacturing_outlined),
                      title: Text(e.name),
                      subtitle: Text('${e.manufacturer} • ${e.model}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => EquipmentDetailPage(equipmentId: e.id)));
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => FriendlyErrorView(error: e, title: 'Couldn’t load equipment', onRetry: () => ref.invalidate(equipmentListProvider)),
            ),
          ),
        ],
      ),
    );
  }
}
