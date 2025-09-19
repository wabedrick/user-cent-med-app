import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class StoragePaginationState {
  final List<Reference> items;
  final String? nextPageToken;
  final bool isLoadingMore;
  const StoragePaginationState({required this.items, this.nextPageToken, this.isLoadingMore = false});
  bool get hasMore => nextPageToken != null;
  StoragePaginationState copy({List<Reference>? items, String? nextPageToken, bool? isLoadingMore}) =>
      StoragePaginationState(items: items ?? this.items, nextPageToken: nextPageToken ?? this.nextPageToken, isLoadingMore: isLoadingMore ?? this.isLoadingMore);
}

class StoragePaginationController extends AsyncNotifier<StoragePaginationState> {
  late final String folder;
  final int pageSize = 20; // fixed size for now

  FirebaseStorage get _storage => FirebaseStorage.instance;

  @override
  Future<StoragePaginationState> build() async {
    // folder should be assigned by factory before first read
    return _loadInitial();
  }

  Future<StoragePaginationState> _loadInitial() async {
    final page = await _fetchPage(null);
    return StoragePaginationState(items: page.items, nextPageToken: page.nextPageToken);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      state = AsyncValue.data(await _loadInitial());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.isLoadingMore) return;
    state = AsyncValue.data(current.copy(isLoadingMore: true));
    try {
      final page = await _fetchPage(current.nextPageToken);
      final merged = current.copy(
        items: [...current.items, ...page.items],
        nextPageToken: page.nextPageToken,
        isLoadingMore: false,
      );
      state = AsyncValue.data(merged);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<_StoragePage> _fetchPage(String? token) async {
    final ref = _storage.ref(folder);
    final result = await ref.list(ListOptions(maxResults: pageSize, pageToken: token));
    return _StoragePage(result.items, result.nextPageToken);
  }
}

class _StoragePage {
  final List<Reference> items;
  final String? nextPageToken;
  _StoragePage(this.items, this.nextPageToken);
}

// Factory method to create a provider for a specific folder.
AsyncNotifierProvider<StoragePaginationController, StoragePaginationState> storageFolderProvider(String folder) {
  return AsyncNotifierProvider<StoragePaginationController, StoragePaginationState>(() {
    final controller = StoragePaginationController();
    controller.folder = folder;
    return controller;
  });
}

final manualsPaginatedProvider = storageFolderProvider('manuals');
final videosPaginatedProvider = storageFolderProvider('videos');