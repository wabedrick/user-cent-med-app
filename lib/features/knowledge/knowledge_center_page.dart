// ignore_for_file: use_build_context_synchronously
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:firebase_storage/firebase_storage.dart';
import '../../repositories/user_repository.dart'; // for userByIdProvider
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // Provides ConsumerStatefulWidget
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/knowledge_link_model.dart';
import '../../repositories/knowledge_links_repository.dart';
import '../../providers/role_provider.dart'; // includes userRoleProvider, firestoreUserRoleProvider, roleClaimProvider
import 'storage_pagination_controller.dart';
import 'package:flutter/services.dart';
import '../../widgets/error_utils.dart';
import '../../repositories/feed_repository.dart';

// Legacy list providers replaced by paginated controllers.

// Use knowledgeLinksProvider from repository (stream-based)

// (Removed global providers for search & equipment filters; using local state instead to avoid analyzer issues)

class KnowledgeCenterPage extends ConsumerStatefulWidget {
  const KnowledgeCenterPage({super.key});
  @override
  ConsumerState<KnowledgeCenterPage> createState() => _KnowledgeCenterPageState();
}

class _KnowledgeCenterPageState extends ConsumerState<KnowledgeCenterPage> {
  bool _uploading = false;
  double _progress = 0;
  String? _currentFileName;
  int _currentFileBytes = 0;
  UploadTask? _currentTask;
  String _searchQuery = '';
  String? _equipmentFilter;

  static const _pdfMaxBytes = 20 * 1024 * 1024; // 20MB
  static const _videoMaxBytes = 200 * 1024 * 1024; // 200MB
  static const _videoExt = ['mp4', 'mov', 'm4v'];
  bool _autoSynced = false;

  bool _validateSelection({required bool isVideo, required PlatformFile file, required ScaffoldMessengerState messenger}) {
    final ext = (file.extension ?? '').toLowerCase();
    if (isVideo) {
      if (!_videoExt.contains(ext)) {
        messenger.showSnackBar(const SnackBar(content: Text('Unsupported video type')));
        return false;
      }
      if (file.size > _videoMaxBytes) {
        messenger.showSnackBar(const SnackBar(content: Text('Video exceeds 200MB limit')));
        return false;
      }
    } else {
      if (ext != 'pdf') {
        messenger.showSnackBar(const SnackBar(content: Text('Only PDF allowed')));
        return false;
      }
      if (file.size > _pdfMaxBytes) {
        messenger.showSnackBar(const SnackBar(content: Text('PDF exceeds 20MB limit')));
        return false;
      }
    }
    return true;
  }

  Future<Reference> _dedupeName(Reference baseRef) async {
    final parent = baseRef.parent!;
    final name = baseRef.name;
    final dot = name.lastIndexOf('.');
    final base = dot == -1 ? name : name.substring(0, dot);
    final ext = dot == -1 ? '' : name.substring(dot);
    int counter = 1;
    Reference candidate = baseRef;
    try {
      final list = await parent.listAll();
      final existing = list.items.map((r) => r.name).toSet();
      while (existing.contains(candidate.name)) {
        candidate = parent.child('${base}_$counter$ext');
        counter++;
      }
    } catch (_) {}
    return candidate;
  }

  Future<void> _pickAndUpload({required bool isVideo}) async {
    if (_uploading) return;
    // Preflight: ensure we have the engineer/admin claim before picking the file to avoid failing late
    final preflightOk = await _ensureClaimForUpload();
    if (!preflightOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload blocked: missing role claim. Try syncing from banner or sign out/in.')));
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context); // capture before async gaps
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, type: FileType.custom, allowedExtensions: isVideo ? _videoExt : ['pdf']);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    if (!_validateSelection(isVideo: isVideo, file: picked, messenger: messenger)) return; // messenger used only synchronously before awaits
    final file = File(picked.path!);
    final storage = FirebaseStorage.instance;
    Reference refTarget = storage.ref(isVideo ? 'videos/${picked.name}' : 'manuals/${picked.name}');
    refTarget = await _dedupeName(refTarget);
    if (!mounted) return;
    setState(() {
      _uploading = true;
      _progress = 0;
      _currentFileName = refTarget.name;
      _currentFileBytes = picked.size;
    });
    bool attemptedClaimSync = false;
    Future<bool> attemptClaimSync() async {
      if (attemptedClaimSync) return false;
      attemptedClaimSync = true;
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('selfSyncRoleClaim');
        final res = await callable.call();
        debugPrint('[UPLOAD] selfSyncRoleClaim result: ${res.data}');
        // Force-refresh ID token and invalidate role providers
        await fa.FirebaseAuth.instance.currentUser?.getIdToken(true);
        if (mounted) {
          ref.invalidate(roleClaimProvider);
          ref.invalidate(userRoleProvider);
        }
        // Small backoff to allow client SDK to pick up new claim
        await Future.delayed(const Duration(milliseconds: 200));
        return true;
      } catch (e) {
        debugPrint('[UPLOAD] selfSyncRoleClaim failed: $e');
        return false;
      }
    }
    final metadata = SettableMetadata(contentType: isVideo ? 'video/mp4' : 'application/pdf');
    try {
      final task = refTarget.putFile(file, metadata);
      _currentTask = task;
      task.snapshotEvents.listen((snap) {
        if (!mounted) return;
        if (snap.totalBytes > 0) {
          setState(() => _progress = snap.bytesTransferred / snap.totalBytes);
        }
      });
      await task;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Uploaded ${refTarget.name}')));
      // Share to feed as a post with a required label (title) and optional description
      try {
        final url = await refTarget.getDownloadURL();
        if (!mounted) return;
        final result = await showDialog<({String title, String caption})?>(
          context: context,
          builder: (dCtx) {
            final titleCtrl = TextEditingController(text: refTarget.name);
            final captionCtrl = TextEditingController();
            return AlertDialog(
              title: Text(isVideo ? 'Publish video to feed' : 'Publish manual to feed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Label (required)', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: captionCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dCtx).pop(null), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    final t = titleCtrl.text.trim();
                    if (t.isEmpty) return; // keep dialog open
                    Navigator.of(dCtx).pop((title: t, caption: captionCtrl.text.trim()));
                  },
                  child: const Text('Publish'),
                ),
              ],
            );
          },
        );
        if (result != null) {
          final user = fa.FirebaseAuth.instance.currentUser;
          if (user != null) {
            // Derive a basic handle placeholder: last segment of displayName/email in lowercase.
            String authorHandle;
            try {
              final u = ref.read(userByIdProvider(user.uid)).value;
              if (u?.username != null && u!.username!.isNotEmpty) {
                authorHandle = u.username!;
              } else {
                final raw = (user.displayName ?? user.email ?? '').trim();
                final parts = raw.split(RegExp(r'\s+'));
                String handleBase = parts.isNotEmpty ? parts.last : raw;
                if (handleBase.contains('@')) handleBase = handleBase.split('@').first;
                authorHandle = handleBase.isEmpty ? 'user' : handleBase.toLowerCase();
              }
            } catch (_) {
              final raw = (user.displayName ?? user.email ?? '').trim();
              final parts = raw.split(RegExp(r'\s+'));
              String handleBase = parts.isNotEmpty ? parts.last : raw;
              if (handleBase.contains('@')) handleBase = handleBase.split('@').first;
              authorHandle = handleBase.isEmpty ? 'user' : handleBase.toLowerCase();
            }
            final feed = ref.read(feedRepositoryProvider);
            if (isVideo) {
              try {
                await feed.createVideoPost(
                  authorId: user.uid,
                  authorName: user.displayName ?? (user.email ?? 'Engineer'),
                  authorHandle: authorHandle,
                  authorAvatarUrl: user.photoURL,
                  title: result.title,
                  caption: result.caption,
                  videoUrl: url,
                  fileName: refTarget.name,
                  // TODO: add durationMs & sizeBytes metadata fields after probing (future enhancement)
                );
              } catch (e) {
                if (mounted) showFriendlyError(context, e, fallback: 'Could not publish video post.');
              }
            } else {
              try {
                await feed.createManualPost(
                  authorId: user.uid,
                  authorName: user.displayName ?? (user.email ?? 'Engineer'),
                  authorHandle: authorHandle,
                  authorAvatarUrl: user.photoURL,
                  title: result.title,
                  caption: result.caption,
                  fileUrl: url,
                  fileName: refTarget.name,
                );
              } catch (e) {
                if (mounted) showFriendlyError(context, e, fallback: 'Could not publish manual post.');
              }
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shared to feed')));
            }
          }
        }
      } catch (_) {}
      if (isVideo) {
        // Refresh video pagination
        await ref.read(videosPaginatedProvider.notifier).refresh();
      } else {
        await ref.read(manualsPaginatedProvider.notifier).refresh();
      }
    } on FirebaseException catch (e, st) {
      debugPrint('[UPLOAD][ERROR][code=${e.code}] message=${e.message}\nStack: $st');
      if (mounted) {
        final code = e.code;
        String friendly = 'Upload failed: $code';
        if (code == 'unauthorized') {
          // Attempt to sync claim if engineer/admin in Firestore but claim missing
          final fsRole = await ref.read(firestoreUserRoleProvider.future);
            final claimRole = await ref.read(roleClaimProvider.future);
          if ((claimRole == null || claimRole.isEmpty) && (fsRole == 'engineer' || fsRole == 'admin')) {
            final synced = await attemptClaimSync();
            if (synced) {
              // Retry once
              try {
                final retryTask = refTarget.putFile(file, metadata);
                _currentTask = retryTask;
                retryTask.snapshotEvents.listen((snap) {
                  if (!mounted) return;
                  if (snap.totalBytes > 0) {
                    setState(() => _progress = snap.bytesTransferred / snap.totalBytes);
                  }
                });
                await retryTask;
                if (mounted) {
                  messenger.showSnackBar(SnackBar(content: Text('Uploaded ${refTarget.name}')));
                  if (isVideo) {
                    await ref.read(videosPaginatedProvider.notifier).refresh();
                  } else {
                    await ref.read(manualsPaginatedProvider.notifier).refresh();
                  }
                }
                return; // success on retry
              } catch (retryErr) {
                debugPrint('[UPLOAD] retry after claim sync failed: $retryErr');
              }
            }
          }
          friendly = 'Upload blocked (role claim missing). Try sign out/in if persists.';
        } else if (code == 'object-not-found') {
          friendly = 'Upload failed: object-not-found (check bucket name and path permissions)';
        }
        messenger.showSnackBar(SnackBar(content: Text(friendly)));
      }
    } catch (e, st) {
      debugPrint('[UPLOAD][ERROR][generic] $e\n$st');
      if (mounted) {
        showFriendlyError(context, e, fallback: 'Upload failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _currentTask = null;
          _currentFileName = null;
          _currentFileBytes = 0;
        });
      }
    }
  }

  /// Ensure the custom claim reflects engineer/admin before Storage writes.
  /// Attempts a self-sync and token refresh if Firestore indicates engineer/admin but claim is missing.
  Future<bool> _ensureClaimForUpload() async {
    try {
      final fsRole = await ref.read(firestoreUserRoleProvider.future);
      final claimRole = await ref.read(roleClaimProvider.future);
      final needsSync = (claimRole == null || claimRole.isEmpty) && (fsRole == 'engineer' || fsRole == 'admin');
      if (!needsSync) return (claimRole == 'engineer' || claimRole == 'admin');
      try {
        final callable = FirebaseFunctions.instance.httpsCallable('selfSyncRoleClaim');
        await callable.call();
        await fa.FirebaseAuth.instance.currentUser?.getIdToken(true);
        if (mounted) {
          ref.invalidate(roleClaimProvider);
          ref.invalidate(userRoleProvider);
        }
        await Future.delayed(const Duration(milliseconds: 200));
        final refreshedClaim = await ref.read(roleClaimProvider.future);
        return refreshedClaim == 'engineer' || refreshedClaim == 'admin';
      } catch (e) {
        debugPrint('[PREUPLOAD] claim sync failed: $e');
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _autoSyncClaimIfNeeded() async {
    if (_autoSynced) return;
    try {
      final diag = await ref.read(roleDiagnosticsProvider.future);
      if ((diag.claim == null || diag.claim!.isEmpty) && (diag.firestore == 'engineer' || diag.firestore == 'admin')) {
        debugPrint('[KC] Auto syncing missing claim (fsRole=${diag.firestore})');
        try {
          final callable = FirebaseFunctions.instance.httpsCallable('selfSyncRoleClaim');
          await callable.call();
          await fa.FirebaseAuth.instance.currentUser?.getIdToken(true);
          if (mounted) ref.invalidate(userRoleProvider);
        } catch (e) {
          debugPrint('[KC] Auto claim sync failed: $e');
        }
        _autoSynced = true; // avoid repeated attempts this session
      }
    } catch (e) {
      debugPrint('[KC] autoSync check failed: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    // Schedule after first frame so providers are ready.
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSyncClaimIfNeeded());
  }

  void _cancelUpload() {
    _currentTask?.cancel();
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final roleAsync = ref.watch(userRoleProvider);
            final canManage = roleAsync.canManageKnowledge;
        return SafeArea(
          child: Wrap(
            children: [
              if (canManage)
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Upload Manual (PDF)'),
                  onTap: () { Navigator.pop(ctx); _pickAndUpload(isVideo: false); },
                ),
              if (canManage)
                ListTile(
                  leading: const Icon(Icons.video_file_outlined),
                  title: const Text('Upload Video (MP4/MOV)'),
                  onTap: () { Navigator.pop(ctx); _pickAndUpload(isVideo: true); },
                ),
                  if (canManage)
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('Upload Image (JPG/PNG)'),
                      onTap: () { Navigator.pop(ctx); _pickAndUploadImage(); },
                    ),
              if (canManage)
                ListTile(
                  leading: const Icon(Icons.add_link),
                  title: const Text('Add External Link'),
                  onTap: () { Navigator.pop(ctx); showDialog(context: context, builder: (_) => const _AddLinkDialog()); },
                ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadImage() async {
    if (_uploading) return;
    final preflightOk = await _ensureClaimForUpload();
    if (!preflightOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload blocked: missing role claim.')));
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(allowMultiple: false, type: FileType.image);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final path = picked.path;
    final bytes = picked.bytes;
    if (path == null && bytes == null) return;
    final storage = FirebaseStorage.instance;
    Reference refTarget = storage.ref('images/${picked.name}');
    refTarget = await _dedupeName(refTarget);
    if (!mounted) return;
    setState(() {
      _uploading = true;
      _progress = 0;
      _currentFileName = refTarget.name;
      _currentFileBytes = picked.size;
    });
    try {
      final data = bytes ?? await File(path!).readAsBytes();
      final upload = refTarget.putData(data, SettableMetadata(contentType: 'image/jpeg'));
      _currentTask = upload;
      upload.snapshotEvents.listen((snap) {
        if (!mounted) return;
        if (snap.totalBytes > 0) {
          setState(() => _progress = snap.bytesTransferred / snap.totalBytes);
        }
      });
      await upload;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Uploaded ${refTarget.name}')));
      try {
        final url = await refTarget.getDownloadURL();
        if (!mounted) return;
        final result = await showDialog<({String title, String caption})?>(
          context: context,
          builder: (dCtx) {
            final titleCtrl = TextEditingController(text: refTarget.name);
            final captionCtrl = TextEditingController();
            return AlertDialog(
              title: const Text('Publish image to feed'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Label (required)', border: OutlineInputBorder())),
                  const SizedBox(height: 8),
                  TextField(controller: captionCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Description (optional)', border: OutlineInputBorder())),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(dCtx).pop(null), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    final t = titleCtrl.text.trim();
                    if (t.isEmpty) return;
                    Navigator.of(dCtx).pop((title: t, caption: captionCtrl.text.trim()));
                  },
                  child: const Text('Publish'),
                ),
              ],
            );
          },
        );
        if (result != null) {
          final user = fa.FirebaseAuth.instance.currentUser;
          if (user != null) {
            final feed = ref.read(feedRepositoryProvider);
            final raw = (user.displayName ?? user.email ?? '').trim();
            final parts = raw.split(RegExp(r'\s+'));
            String handleBase = parts.isNotEmpty ? parts.last : raw;
            if (handleBase.contains('@')) handleBase = handleBase.split('@').first;
            final authorHandle = handleBase.isEmpty ? 'user' : handleBase.toLowerCase();
            await feed.createImagePost(
              authorId: user.uid,
              authorName: user.displayName ?? (user.email ?? 'Engineer'),
              authorHandle: authorHandle,
              authorAvatarUrl: user.photoURL,
              title: result.title,
              caption: result.caption,
              imageUrls: [url],
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shared to feed')));
            }
          }
        }
      } catch (_) {}
    } catch (e) {
      if (mounted) showFriendlyError(context, e, fallback: 'Upload failed.');
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _currentTask = null;
          _currentFileName = null;
          _currentFileBytes = 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
  final roleAsync = ref.watch(userRoleProvider);
  final canManage = roleAsync.canManageKnowledge;
  final diagAsync = ref.watch(roleDiagnosticsProvider);
  final manuals = ref.watch(manualsPaginatedProvider);
    final videos = ref.watch(videosPaginatedProvider);
    final links = ref.watch(knowledgeLinksProvider);
    final query = _searchQuery.trim().toLowerCase();
    final equipmentFilter = _equipmentFilter;
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('Knowledge Center')),
          floatingActionButton: FloatingActionButton(
            onPressed: canManage ? _showAddMenu : null,
            child: const Icon(Icons.add),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await ref.read(manualsPaginatedProvider.notifier).refresh();
              await ref.read(videosPaginatedProvider.notifier).refresh();
              ref.invalidate(knowledgeLinksProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Claim mismatch / missing banner
                diagAsync.when(
                  data: (d) {
                    if ((d.claim == null || d.claim!.isEmpty) && (d.firestore == 'engineer' || d.firestore == 'admin')) {
                      return Card(
                        color: Colors.amber.shade100,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Role claim not yet applied', style: TextStyle(fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    const Text('Your Firestore role is engineer/admin but the auth token is missing the role claim. Sync it to enable uploads.'),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      children: [
                                        ElevatedButton.icon(
                                          onPressed: () async {
                                            try {
                                              final callable = FirebaseFunctions.instance.httpsCallable('selfSyncRoleClaim');
                                              await callable.call();
                                              await fa.FirebaseAuth.instance.currentUser?.getIdToken(true);
                                              ref.invalidate(userRoleProvider);
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Role claim synced')));
                                            } catch (e) {
                                              showFriendlyError(context, e, fallback: 'Could not sync. Please try again.');
                                            }
                                          },
                                          icon: const Icon(Icons.sync),
                                          label: const Text('Sync role claim'),
                                        ),
                                        OutlinedButton(
                                          onPressed: () async { try { await fa.FirebaseAuth.instance.signOut(); } catch (_) {} },
                                          child: const Text('Sign out / in'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 12),
                _SearchAndFilterBar(
                  canManage: canManage,
                  searchQuery: _searchQuery,
                  equipmentFilter: _equipmentFilter,
                  onSearchChanged: (v) => setState(() => _searchQuery = v),
                  onEquipmentFilterChanged: (v) => setState(() => _equipmentFilter = (v?.isEmpty ?? true) ? null : v),
                  onAddPressed: _showAddMenu,
                ),
                const SizedBox(height: 24),
                _SectionHeader(title: 'Manuals', onUpload: canManage ? () => _pickAndUpload(isVideo: false) : null, icon: Icons.upload_file),
                const SizedBox(height: 8),
                manuals.when(
                  data: (stateData) {
                    final notifier = ref.read(manualsPaginatedProvider.notifier);
                    var items = stateData.items;
                    if (query.isNotEmpty) {
                      items = items.where((r) => r.name.toLowerCase().contains(query)).toList();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (items.isEmpty) const _Empty(text: 'No manuals uploaded yet') else ...items.map((r) => _StorageItemTile(ref: r)),
                        if (stateData.hasMore)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: OutlinedButton(
                              onPressed: stateData.isLoadingMore ? null : () => notifier.loadMore(),
                              child: stateData.isLoadingMore ? const SizedBox(height:16,width:16,child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                  error: (e, _) => _ErrorInline(msg: 'Couldn’t list manuals'),
                ),
                const SizedBox(height: 24),
                if (canManage) ...[
                  _SectionHeader(title: 'Videos', onUpload: canManage ? () => _pickAndUpload(isVideo: true) : null, icon: Icons.video_file_outlined),
                  const SizedBox(height: 8),
                  videos.when(
                    data: (stateData) {
                      final notifier = ref.read(videosPaginatedProvider.notifier);
                      var items = stateData.items;
                      if (query.isNotEmpty) {
                        items = items.where((r) => r.name.toLowerCase().contains(query)).toList();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (items.isEmpty) const _Empty(text: 'No videos uploaded yet') else ...items.map((r) => _StorageItemTile(ref: r)),
                          if (stateData.hasMore)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: OutlinedButton(
                                onPressed: stateData.isLoadingMore ? null : () => notifier.loadMore(),
                                child: stateData.isLoadingMore ? const SizedBox(height:16,width:16,child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
                              ),
                            ),
                        ],
                      );
                    },
                    loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                    error: (e, _) => _ErrorInline(msg: 'Couldn’t list videos'),
                  ),
                  const SizedBox(height: 24),
                  _SectionHeader(title: 'Images', onUpload: canManage ? _pickAndUploadImage : null, icon: Icons.image_outlined),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final images = ref.watch(imagesPaginatedProvider);
                      return images.when(
                        data: (stateData) {
                          final notifier = ref.read(imagesPaginatedProvider.notifier);
                          var items = stateData.items;
                          if (query.isNotEmpty) {
                            items = items.where((r) => r.name.toLowerCase().contains(query)).toList();
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (items.isEmpty) const _Empty(text: 'No images uploaded yet') else ...items.map((r) => _StorageItemTile(ref: r)),
                              if (stateData.hasMore)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton(
                                    onPressed: stateData.isLoadingMore ? null : () => notifier.loadMore(),
                                    child: stateData.isLoadingMore ? const SizedBox(height:16,width:16,child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Load more'),
                                  ),
                                ),
                            ],
                          );
                        },
                        loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                        error: (e, _) => _ErrorInline(msg: 'Couldn’t list images'),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
                const Text('External Links', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                links.when(
                  data: (items) {
                    var filtered = items;
                    if (query.isNotEmpty) {
                      filtered = filtered.where((l) => l.title.toLowerCase().contains(query) || l.url.toLowerCase().contains(query)).toList();
                    }
                    if (equipmentFilter != null && equipmentFilter.trim().isNotEmpty) {
                      filtered = filtered.where((l) => (l.equipmentId ?? '').toLowerCase() == equipmentFilter.toLowerCase()).toList();
                    }
                    if (filtered.isEmpty) return const _Empty(text: 'No saved links yet');
                    return Column(children: filtered.map((l) => _LinkTile(link: l)).toList());
                  },
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
                  error: (e, _) => _ErrorInline(msg: 'Couldn’t list links'),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
        if (_uploading)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null, strokeWidth: 6),
                            Text('${(_progress * 100).clamp(0, 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Removed the 'Uploading ...' text; show only percentage via the progress indicator
                      if (_currentFileName != null) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            _currentFileName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null),
                      ),
                      if (_currentFileBytes > 0) ...[
                        const SizedBox(height: 8),
                        Text(_humanReadableBytes(_currentFileBytes), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _cancelUpload,
                        icon: const Icon(Icons.cancel, color: Colors.white70),
                        label: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

String _humanReadableBytes(int bytes) {
  const units = ['B','KB','MB','GB'];
  double size = bytes.toDouble();
  int unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return '${size.toStringAsFixed(size < 10 ? 1 : 0)} ${units[unitIndex]}';
}

class _StorageItemTile extends ConsumerStatefulWidget {
  final Reference ref;
  const _StorageItemTile({required this.ref});
  @override
  ConsumerState<_StorageItemTile> createState() => _StorageItemTileState();
}

class _StorageItemTileState extends ConsumerState<_StorageItemTile> {
  bool _downloading = false;
  String? _localPath;

  Future<void> _downloadAndOpen() async {
    setState(() => _downloading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${widget.ref.name}');
      await widget.ref.writeToFile(file);
      setState(() => _localPath = file.path);
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
  showFriendlyError(context, e, fallback: 'Download failed. Please try again.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(userRoleProvider);
  final isAdmin = roleAsync.isAdmin;
  final isEngineer = roleAsync.isEngineer;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(widget.ref.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_localPath == null ? widget.ref.fullPath : 'Saved: $_localPath', maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_downloading)
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(tooltip: 'Download & open', icon: const Icon(Icons.download_outlined), onPressed: _downloadAndOpen),
            IconButton(
              tooltip: 'Copy URL',
              icon: const Icon(Icons.link),
              onPressed: () async {
                try {
                  final url = await widget.ref.getDownloadURL();
                  await Clipboard.setData(ClipboardData(text: url));
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copied')));
                } catch (e) {
                  if (mounted) showFriendlyError(context, e, fallback: 'Could not copy to clipboard.');
                }
              },
            ),
            if (isAdmin || isEngineer)
              IconButton(
                tooltip: 'Delete file',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete File?'),
                      content: Text('Permanently delete ${widget.ref.name}?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await widget.ref.delete();
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                    // Trigger refresh of whichever list this belongs to
                    if (widget.ref.fullPath.startsWith('manuals/')) {
                      await ref.read(manualsPaginatedProvider.notifier).refresh();
                    } else if (widget.ref.fullPath.startsWith('videos/')) {
                      await ref.read(videosPaginatedProvider.notifier).refresh();
                    } else if (widget.ref.fullPath.startsWith('images/')) {
                      await ref.read(imagesPaginatedProvider.notifier).refresh();
                    }
                  } catch (e) {
                    if (mounted) showFriendlyError(context, e, fallback: 'Could not delete.');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkTile extends ConsumerWidget {
  final KnowledgeLink link;
  const _LinkTile({required this.link});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isVideo = link.type == 'video';
    final roleAsync = ref.watch(userRoleProvider);
    final isAdmin = roleAsync.isAdmin;
    return Card(
      child: ListTile(
        leading: Icon(isVideo ? Icons.ondemand_video_outlined : Icons.picture_as_pdf_outlined, color: isVideo ? Colors.redAccent : Colors.indigo),
        title: Text(link.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                final uri = Uri.tryParse(link.url);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
            ),
            IconButton(
              tooltip: 'Copy URL',
              icon: const Icon(Icons.link),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link.url));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copied')));
              },
            ),
            if (isAdmin)
              IconButton(
                tooltip: 'Delete link',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete Link?'),
                      content: Text('Remove link "${link.title}"?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  try {
                    await ref.read(knowledgeLinksRepositoryProvider).delete(link.id);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link deleted')));
                  } catch (e) {
                    showFriendlyError(context, e, fallback: 'Could not delete.');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onUpload;
  final IconData icon;
  const _SectionHeader({required this.title, required this.icon, this.onUpload});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        if (onUpload != null)
          IconButton(
            tooltip: 'Upload',
            onPressed: onUpload,
            icon: Icon(icon),
          ),
      ],
    );
  }
}

class _SearchAndFilterBar extends StatelessWidget {
  final bool canManage;
  final String searchQuery;
  final String? equipmentFilter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onEquipmentFilterChanged;
  final VoidCallback onAddPressed;
  const _SearchAndFilterBar({
    required this.canManage,
    required this.searchQuery,
    required this.equipmentFilter,
    required this.onSearchChanged,
    required this.onEquipmentFilterChanged,
    required this.onAddPressed,
  });
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search manuals, videos, links'),
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Equipment ID filter',
                  suffixIcon: equipmentFilter == null || equipmentFilter!.isEmpty
                      ? const Icon(Icons.qr_code_2)
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => onEquipmentFilterChanged(null),
                        ),
                ),
                onChanged: (v) => onEquipmentFilterChanged(v.isEmpty ? null : v),
              ),
            ),
            if (canManage) const SizedBox(width: 12),
            if (canManage)
              ElevatedButton.icon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
          ],
        ),
      ],
    );
  }
}

class _AddLinkDialog extends ConsumerStatefulWidget {
  const _AddLinkDialog();
  @override
  ConsumerState<_AddLinkDialog> createState() => _AddLinkDialogState();
}

class _AddLinkDialogState extends ConsumerState<_AddLinkDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _url = TextEditingController();
  String _type = 'video';
  final _equipmentId = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _equipmentId.dispose();
    super.dispose();
  }

  String? _validateUrl(String? v) {
    if (v == null || v.trim().isEmpty) return 'Enter a URL';
    final u = v.trim();
    final ok = u.startsWith('http://') || u.startsWith('https://');
    if (!ok) return 'URL must start with http(s)://';
    if (_type == 'video') {
      // Basic YouTube hint only (not strict): youtube.com or youtu.be
      if (!(u.contains('youtube.com') || u.contains('youtu.be'))) return 'Expected a YouTube link';
    } else {
      if (!u.toLowerCase().endsWith('.pdf')) return 'Expected a .pdf link';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add External Link'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => (v==null||v.trim().isEmpty)?'Required':null),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: const [
                DropdownMenuItem(value: 'video', child: Text('YouTube video')),
                DropdownMenuItem(value: 'pdf', child: Text('PDF document')),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'video'),
            ),
            const SizedBox(height: 8),
            TextFormField(controller: _url, decoration: const InputDecoration(labelText: 'URL'), validator: _validateUrl),
            const SizedBox(height: 8),
            TextFormField(controller: _equipmentId, decoration: const InputDecoration(labelText: 'Equipment ID (optional)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  if (!_formKey.currentState!.validate()) return;
                  setState(() => _saving = true);
                  try {
                    // Retrieve uid via FirebaseAuth to satisfy rules
                    final user = await fa.FirebaseAuth.instance.authStateChanges().first;
                    if (user == null) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in required')));
                      setState(() => _saving = false);
                      return;
                    }
                    try {
                      await ref.read(knowledgeLinksRepositoryProvider).create(
                        title: _title.text.trim(),
                        url: _url.text.trim(),
                        type: _type,
                        equipmentId: _equipmentId.text.trim().isEmpty ? null : _equipmentId.text.trim(),
                        createdBy: user.uid,
                      );
                      if (context.mounted) {
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link added')));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        showFriendlyError(context, e, fallback: 'Could not save link.');
                      }
                    } finally {
                      if (mounted) setState(() => _saving = false);
                    }
                  } catch (e) {
                    if (context.mounted) {
                      showFriendlyError(context, e, fallback: 'Operation failed. Please try again.');
                    }
                    setState(() => _saving = false);
                  }
                },
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: Text(text, style: const TextStyle(color: Colors.black54))));
}

class _ErrorInline extends StatelessWidget {
  final String msg;
  const _ErrorInline({required this.msg});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Center(child: Text(msg, style: const TextStyle(color: Colors.redAccent))));
}
