import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/error_utils.dart';
import '../repositories/equipment_repository.dart';

class EquipmentDetailPage extends ConsumerWidget {
  final String equipmentId;
  const EquipmentDetailPage({super.key, required this.equipmentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eq = ref.watch(equipmentByIdProvider(equipmentId));
    return Scaffold(
      appBar: AppBar(title: const Text('Equipment Details')),
      body: eq.when(
        data: (e) {
          if (e == null) return const Center(child: Text('Not found'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(title: Text(e.name, style: Theme.of(context).textTheme.titleLarge), subtitle: Text('Model: ${e.model}')),
              const SizedBox(height: 8),
              ListTile(leading: const Icon(Icons.factory_outlined), title: const Text('Manufacturer'), subtitle: Text(e.manufacturer)),
              const Divider(height: 24),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf_outlined),
                title: const Text('Manual (PDF)'),
                subtitle: Text(e.manualPdfUrl.isEmpty ? 'Not provided' : e.manualPdfUrl),
                trailing: ElevatedButton(
                  onPressed: e.manualPdfUrl.isEmpty ? null : () async {
                    final uri = Uri.tryParse(e.manualPdfUrl);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  child: const Text('Open'),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.ondemand_video_outlined),
                title: const Text('Video Tutorial'),
                subtitle: Text(e.videoTutorialUrl.isEmpty ? 'Not provided' : e.videoTutorialUrl),
                trailing: ElevatedButton(
                  onPressed: e.videoTutorialUrl.isEmpty ? null : () async {
                    final uri = Uri.tryParse(e.videoTutorialUrl);
                    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                  },
                  child: const Text('Open'),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FriendlyErrorView(error: e, title: 'Couldn’t load details'),
      ),
    );
  }
}
