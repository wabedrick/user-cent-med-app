import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'wakelock_helper.dart';

class VideoPlayerPage extends StatefulWidget {
  final String url;
  final String? title;
  const VideoPlayerPage({super.key, required this.url, this.title});

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final VideoPlayerController _controller;
  bool _initialized = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
        // Manage wakelock based on play state
        if (_controller.value.isPlaying) {
          WakelockHelper.acquire();
        } else {
          WakelockHelper.release();
        }
      })
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _initialized = true);
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _error = true);
      });
  }

  @override
  void dispose() {
    // Ensure wakelock is released when leaving page
    WakelockHelper.release();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Video')),
      body: _error
          ? const Center(child: Text('Could not load video'))
          : Center(
              child: AspectRatio(
                aspectRatio: _initialized && _controller.value.aspectRatio > 0
                    ? _controller.value.aspectRatio
                    : 16 / 9,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_initialized)
                      VideoPlayer(_controller)
                    else
                      const Center(child: CircularProgressIndicator()),
                    Positioned(
                      bottom: 12,
                      left: 12,
                      right: 12,
                      child: _Controls(controller: _controller, initialized: _initialized),
                    )
                  ],
                ),
              ),
            ),
    );
  }
}

class _Controls extends StatefulWidget {
  final VideoPlayerController controller;
  final bool initialized;
  const _Controls({required this.controller, required this.initialized});
  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _dragging = false;

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.controller.value;
    final pos = v.position;
    final dur = v.duration;
    final playing = v.isPlaying;

    return Card(
      color: Colors.black.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  icon: Icon(playing ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
                  onPressed: !widget.initialized
                      ? null
                      : () {
                          if (playing) {
                            widget.controller.pause();
                          } else {
                            widget.controller.play();
                          }
                        },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: dur.inMilliseconds == 0
                        ? 0
                        : (_dragging ? pos : widget.controller.value.position).inMilliseconds.clamp(0, dur.inMilliseconds).toDouble(),
                    min: 0,
                    max: dur.inMilliseconds == 0 ? 1 : dur.inMilliseconds.toDouble(),
                    onChangeStart: (_) => setState(() => _dragging = true),
                    onChangeEnd: (_) => setState(() => _dragging = false),
                    onChanged: !widget.initialized
                        ? null
                        : (v) async {
                            final target = Duration(milliseconds: v.toInt());
                            await widget.controller.seekTo(target);
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_format(pos)} / ${_format(dur)}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Replay 10s',
                  icon: const Icon(Icons.replay_10, color: Colors.white),
                  onPressed: !widget.initialized
                      ? null
                      : () async {
                          final p = widget.controller.value.position;
                          await widget.controller.seekTo(p - const Duration(seconds: 10));
                        },
                ),
                IconButton(
                  tooltip: 'Forward 10s',
                  icon: const Icon(Icons.forward_10, color: Colors.white),
                  onPressed: !widget.initialized
                      ? null
                      : () async {
                          final p = widget.controller.value.position;
                          await widget.controller.seekTo(p + const Duration(seconds: 10));
                        },
                ),
                IconButton(
                  tooltip: 'Fullscreen',
                  icon: const Icon(Icons.fullscreen, color: Colors.white),
                  onPressed: () {
                    // Placeholder; can implement full-screen route if needed
                  },
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
