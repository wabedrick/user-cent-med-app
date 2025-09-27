import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';
import '../repositories/feed_repository.dart';

class PaginatedFeedState {
  final List<Post> posts;
  final bool loadingInitial;
  final bool loadingMore;
  final bool reachedEnd;
  final String? errorMessage;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;

  const PaginatedFeedState({
    required this.posts,
    required this.loadingInitial,
    required this.loadingMore,
    required this.reachedEnd,
    required this.errorMessage,
    required this.lastDoc,
  });

  factory PaginatedFeedState.initial() => const PaginatedFeedState(
        posts: [],
        loadingInitial: true,
        loadingMore: false,
        reachedEnd: false,
        errorMessage: null,
        lastDoc: null,
      );

  PaginatedFeedState copyWith({
    List<Post>? posts,
    bool? loadingInitial,
    bool? loadingMore,
    bool? reachedEnd,
    String? errorMessage,
    DocumentSnapshot<Map<String, dynamic>>? lastDoc,
    bool clearError = false,
  }) => PaginatedFeedState(
        posts: posts ?? this.posts,
        loadingInitial: loadingInitial ?? this.loadingInitial,
        loadingMore: loadingMore ?? this.loadingMore,
        reachedEnd: reachedEnd ?? this.reachedEnd,
        errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
        lastDoc: lastDoc ?? this.lastDoc,
      );
}

class PaginatedFeedNotifier extends Notifier<PaginatedFeedState> {
  late FeedRepository _repo;
  final int pageSize = 12;
  bool _loadedOnce = false;

  @override
  PaginatedFeedState build() {
    _repo = ref.read(feedRepositoryProvider);
    if (!_loadedOnce) {
      _loadedOnce = true;
      Future.microtask(loadInitial);
    }
    return PaginatedFeedState.initial();
  }

  Future<void> loadInitial() async {
    // Set loadingInitial true
    state = PaginatedFeedState.initial();
    try {
      final page = await _repo.fetchPage(limit: pageSize);
      state = state.copyWith(
        posts: page.posts,
        lastDoc: page.last,
        loadingInitial: false,
        reachedEnd: page.posts.length < pageSize,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loadingInitial: false, errorMessage: e.toString());
    }
  }

  Future<void> loadMore() async {
    final s = state; // snapshot
    if (s.loadingMore || s.reachedEnd || s.loadingInitial) return;
    state = s.copyWith(loadingMore: true);
    try {
      final page = await _repo.fetchPage(startAfter: state.lastDoc, limit: pageSize);
      if (page.posts.isEmpty) {
        state = state.copyWith(loadingMore: false, reachedEnd: true);
      } else {
        state = state.copyWith(
          posts: [...state.posts, ...page.posts],
          lastDoc: page.last,
          loadingMore: false,
          reachedEnd: page.posts.length < pageSize,
        );
      }
    } catch (e) {
      state = state.copyWith(loadingMore: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    await loadInitial();
  }

  /// Optimistically prepend newly detected head posts.
  void prependPosts(List<Post> newPosts) {
    if (newPosts.isEmpty) return;
    // Filter out any that already exist.
    final existingIds = state.posts.map((p) => p.id).toSet();
    final toInsert = newPosts.where((p) => !existingIds.contains(p.id)).toList();
    if (toInsert.isEmpty) return;
    state = state.copyWith(posts: [...toInsert, ...state.posts]);
  }
}

final paginatedFeedProvider = NotifierProvider.autoDispose<PaginatedFeedNotifier, PaginatedFeedState>(
  PaginatedFeedNotifier.new,
);
