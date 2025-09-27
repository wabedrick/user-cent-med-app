import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'wakelock_helper.dart';

class MiniVideoState {
  final String url;
  final String? title;
  MiniVideoState({required this.url, this.title});
}

class MiniVideoNotifier extends Notifier<MiniVideoState?> {
  @override
  MiniVideoState? build() => null;

  void show(String url, {String? title}) => state = MiniVideoState(url: url, title: title);
  void close() => state = null;
}

final miniVideoProvider = NotifierProvider<MiniVideoNotifier, MiniVideoState?>(MiniVideoNotifier.new);

class MiniVideoOverlay extends ConsumerStatefulWidget {
  const MiniVideoOverlay({super.key});
  @override
  ConsumerState<MiniVideoOverlay> createState() => _MiniVideoOverlayState();
}

class _MiniVideoOverlayState extends ConsumerState<MiniVideoOverlay> {
  VideoPlayerController? _controller;
  bool _init = false;
  bool _locked = false;

  @override
  void didUpdateWidget(covariant MiniVideoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _ensureController(String url) async {
    if (_controller != null && _controller!.dataSource == url) return;
    _disposeController();
    _controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller!.addListener(() {
      if (!mounted) return;
      final playing = _controller!.value.isPlaying;
      if (playing && !_locked) {
        _locked = true;
        WakelockHelper.acquire();
      } else if (!playing && _locked) {
        _locked = false;
        WakelockHelper.release();
      }
      setState(() {});
    });
    await _controller!.initialize();
    await _controller!.setLooping(true);
    setState(() => _init = true);
  }

  void _disposeController() {
    if (_locked) {
      _locked = false;
      WakelockHelper.release();
    }
    _controller?.dispose();
    _controller = null;
    _init = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(miniVideoProvider);
    if (state == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: DraggableScrollableSheet(
          initialChildSize: 0.25,
          minChildSize: 0.18,
          maxChildSize: 0.6,
          builder: (ctx, scroll) {
            return GestureDetector(
              onTap: () async {
                // Toggle play/pause on tap
                if (_controller == null) return;
                if (_controller!.value.isPlaying) {
                  await _controller!.pause();
                } else {
                  await _controller!.play();
                }
              },
              child: FutureBuilder(
                future: _ensureController(state.url),
                builder: (ctx, snap) {
                  return Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        Container(color: Colors.black, child: _init && _controller != null ? AspectRatio(aspectRatio: _controller!.value.aspectRatio, child: VideoPlayer(_controller!)) : const Center(child: CircularProgressIndicator())),
                        Positioned(
                          top: 6,
                          left: 8,
                          right: 48,
                          child: Text(state.title ?? 'Video', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white)),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              ref.read(miniVideoProvider.notifier).close();
                              WakelockHelper.release();
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
