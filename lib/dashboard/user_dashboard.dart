import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme.dart';
import '../auth/sign_in_screen.dart';
import '../repositories/repair_requests_repository.dart';
import '../repositories/equipment_repository.dart';
import '../widgets/error_utils.dart';
// Feed imports (moved from bottom reintegration section)
import '../repositories/feed_repository.dart';
import '../models/post_model.dart';
import '../repositories/user_repository.dart';
import '../providers/paginated_feed_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../features/video/mini_video_overlay.dart';
import 'package:video_player/video_player.dart';
import '../features/video/wakelock_helper.dart';
// Removed unused feed & role related imports during cleanup of corrupted section
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
// Software decode fallback (media_kit)
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'dart:typed_data';
import 'dart:async'; // for Timer
import '../providers/role_provider.dart';
import '../providers/consult_providers.dart';
import '../main.dart' show pendingConsultNavigationProvider;
import '../models/consult_request_model.dart';

// ---------------- User dashboard models & providers (restored) ----------------
enum Urgency { low, medium, high }
class NurseTaskSummary {
  final String equipmentName;
  final String note;
  final Urgency urgency;
  NurseTaskSummary(this.equipmentName, this.note, {required this.urgency});
}

class QuickStats {
  final int assigned;
  final int dueSoon;
  final int overdue;
  final int resolvedToday;
  const QuickStats({required this.assigned, required this.dueSoon, required this.overdue, required this.resolvedToday});
}

final nurseTasksProvider = FutureProvider<List<NurseTaskSummary>>((ref) async {
  await Future.delayed(const Duration(milliseconds: 350));
  return [
    NurseTaskSummary('Infusion Pump', 'Tubing replacement due', urgency: Urgency.medium),
    NurseTaskSummary('Ventilator', 'Filter check overdue', urgency: Urgency.high),
    NurseTaskSummary('ECG Monitor', 'Running nominal', urgency: Urgency.low),
  ];
});

final quickStatsProvider = FutureProvider<QuickStats>((ref) async {
  await Future.delayed(const Duration(milliseconds: 250));
  return const QuickStats(assigned: 12, dueSoon: 3, overdue: 1, resolvedToday: 5);
});

// ---------------- UserDashboardScreen (restored minimal scaffold) -------------
class UserDashboardScreen extends ConsumerStatefulWidget {
  const UserDashboardScreen({super.key});
  @override
  ConsumerState<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends ConsumerState<UserDashboardScreen> {
  int tab = 0;
  String? _lastPendingConsultId;
  Timer? _bannerTimer;
  OverlayEntry? _bannerEntry;
  // Track when a consult highlight should expire
  DateTime? _highlightExpiresAt;
  Timer? _highlightTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerEntry?.remove();
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _showAnswerBanner(String consultId) {
    _bannerEntry?.remove();
  final overlay = Overlay.of(context); // non-null in modern Flutter
    final entry = OverlayEntry(
      builder: (ctx) => SafeArea(
        child: Semantics(
          label: 'Consult answered banner',
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
            child: Material(
              color: Colors.transparent,
              child: Dismissible(
                key: const ValueKey('consult_answered_banner'),
                direction: DismissDirection.up,
                onDismissed: (_) {
                  _bannerTimer?.cancel();
                  _bannerEntry?.remove();
                  _bannerEntry = null;
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0,5))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.mark_chat_read_outlined, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(child: Text('An engineer answered your consult', style: GoogleFonts.montserrat(color: Colors.white, fontWeight: FontWeight.w600)) ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () {
                          _bannerTimer?.cancel();
                          _bannerEntry?.remove();
                          _bannerEntry = null;
                        },
                        icon: const Icon(Icons.close, size: 18, color: Colors.white70),
                      ),
                      TextButton(
                        onPressed: () {
                          final titles = <String>['Feed', 'Consult', 'Requests', 'History', 'Profile'];
                          final idx = titles.indexOf('Consult');
                          if (idx != -1) {
                            setState(() => tab = idx);
                          }
                          _bannerTimer?.cancel();
                          _bannerEntry?.remove();
                          _bannerEntry = null;
                        },
                        child: const Text('View', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _bannerEntry = entry;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), () { _bannerEntry?.remove(); _bannerEntry = null; });
  }
  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(userRoleProvider);
    final role = roleAsync.value; // may be null while loading
  // role may be null while loading; treat null as basic user
  final isBasicUser = role == 'user' || role == null; // ordering avoids unnecessary null comparison lint
    // Detect pending consult navigation request (incoming consult_new or consult_answered)
  final pendingId = ref.watch(pendingConsultNavigationProvider);
    if (pendingId != null && pendingId != _lastPendingConsultId) {
      _lastPendingConsultId = pendingId;
      // Start / reset highlight expiry (4 seconds)
      _highlightExpiresAt = DateTime.now().add(const Duration(seconds: 4));
      _highlightTimer?.cancel();
      _highlightTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() {}); // triggers rebuild to drop highlight
      });
      // If answered notification (we cannot distinguish here easily; banner always for answered soon when highlight occurs) show banner
      // Heuristic: if user not on Consult tab -> switch automatically only for answered (we can't know). We'll switch only if not on Consult.
      final titles = <String>['Feed', 'Consult', 'Requests', 'History', 'Profile'];
      final consultIndex = titles.indexOf('Consult');
      if (tab != consultIndex) {
        // Don't immediately switch; show banner instead. User can tap banner or we auto highlight when they navigate.
        _showAnswerBanner(pendingId);
      }
    }
  // Removed 'Tasks' from user navigation per request
  final baseTitles = <String>['Feed', 'Consult', 'Requests', 'History', 'Profile'];
    final titles = baseTitles; // Overview removed globally
    if (tab >= titles.length) tab = 0;
    final title = titles[(tab >= 0 && tab < titles.length) ? tab : 0];
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 900;
    return Scaffold(
      drawer: isNarrow ? Drawer(
        child: SafeArea(
          child: _UserSideNavDynamic(
            currentIndex: tab,
            onSelect: (i){ setState(()=>tab=i); Navigator.of(context).maybePop();},
            titles: titles,
          ),
        ),
      ) : null,
      body: SafeArea(
        child: Row(
          children: [
            if (!isNarrow)
              SizedBox(
                width: 220,
                child: _UserSideNavDynamic(
                  currentIndex: tab,
                  onSelect: (i)=>setState(()=>tab=i),
                  titles: titles,
                ),
              ),
            Expanded(
              child: Column(
                children: [
                  _UserHeaderBar(
                    title: title,
                    showMenu: isNarrow,
                    onConsultTap: () {
                      final consultIndex = titles.indexOf('Consult');
                      if (consultIndex != -1) {
                        setState(() => tab = consultIndex);
                      }
                    },
                  ),
                  const Divider(height: 1),
                  Expanded(child: _UserBody(tab: tab, titles: titles, isBasicUser: isBasicUser)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// ---------------- Unified InlineVideoPlayer (clean) ----------------
class InlineVideoPlayer extends ConsumerStatefulWidget {
  final String url;
  final String? title;
  const InlineVideoPlayer({super.key, required this.url, this.title});
  @override
  ConsumerState<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends ConsumerState<InlineVideoPlayer> {
  VideoPlayerController? _controller; // hardware / standard controller
  bool _init = false;
  bool _error = false;
  bool _finalError = false; // marks that all fallbacks exhausted & error is definitive
  String? _errorMessage;
  String? _preflightInfo;
  bool _showControls = true;
  bool _loading = false;
  bool _muted = false;
  DateTime _lastInteraction = DateTime.now();
  static const _controlsVisibleDuration = Duration(seconds: 3);

  // Local file fallback
  File? _localFile;
  bool _triedLocal = false;

  // Software decode (media_kit) fallback (manual trigger)
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkVideoController;
  bool _softwareMode = false;
  bool _softwareTried = false;
  bool _autoSoftwareTried = false; // ensure we only auto-trigger software fallback once
  // Diagnostics
  final List<String> _logLines = [];
  bool _showDetails = false;
  void _log(String msg) {
    final line = '[InlineVideoPlayer] ${DateTime.now().toIso8601String()} $msg';
    debugPrint(line);
    if (_logLines.length > 120) _logLines.removeAt(0);
    _logLines.add(line);
  }

  // Thumbnail
  Uint8List? _thumb;
  bool _thumbRequested = false;

  @override
  void initState() {
    super.initState();
    _generateThumb();
  }

  Future<void> _generateThumb() async {
    if (_thumbRequested) return; // avoid duplicate work
    _thumbRequested = true;
    try {
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: widget.url,
        imageFormat: vt.ImageFormat.PNG,
        maxHeight: 320,
        quality: 60,
        timeMs: 0,
      );
      if (!mounted) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() => _thumb = bytes);
      }
    } catch (e) {
      debugPrint('[InlineVideoPlayer] thumbnail generation failed: $e');
    }
  }

  void _scheduleAutoHide() {
    _lastInteraction = DateTime.now();
    if (!_showControls) setState(() => _showControls = true);
  }

  Future<void> _preflight() async {
    try {
      final uri = Uri.parse(widget.url);
      http.Response? headResp;
      try {
        final headReq = http.Request('HEAD', uri);
        final streamed = await headReq.send().timeout(const Duration(seconds: 8));
        headResp = await http.Response.fromStream(streamed);
      } catch (_) {
        try {
          headResp = await http.get(uri, headers: const {'range': 'bytes=0-0'}).timeout(const Duration(seconds: 8));
        } catch (e2) {
          _log('preflight fallback GET failed: $e2');
        }
      }
      if (headResp != null) {
        final ct = headResp.headers['content-type'];
        final cl = headResp.headers['content-length'];
        final acceptRanges = headResp.headers['accept-ranges'];
        _preflightInfo = 'HTTP ${headResp.statusCode} • ${ct ?? 'no-ct'} • ${cl ?? '?'}${acceptRanges != null ? ' • ranges' : ''}';
        _log('preflight http=${headResp.statusCode} ct=$ct len=$cl ranges=${acceptRanges != null}');
        if (headResp.statusCode >= 400) {
          _error = true;
          _errorMessage = 'HTTP ${headResp.statusCode}';
        } else if (ct != null && !ct.startsWith('video/')) {
          _log('non-video content-type: $ct');
        }
      }
      // Try partial range for atom probe (first 128KB)
      try {
        final partial = await http.get(uri, headers: {'Range': 'bytes=0-131071'}).timeout(const Duration(seconds: 10));
        if (partial.statusCode == 206 || partial.statusCode == 200) {
          final atoms = _probeMp4Atoms(partial.bodyBytes);
          if (atoms.isNotEmpty) {
            _preflightInfo = '${_preflightInfo ?? ''} atoms:${atoms.join('|')}';
          }
          _log('atom order: ${atoms.join('>')}');
        } else {
          _log('atom probe status=${partial.statusCode}');
        }
      } catch (e) {
        _log('atom probe failed: $e');
      }
    } catch (e) {
      _log('preflight exception: $e');
    }
  }

  List<String> _probeMp4Atoms(Uint8List bytes) {
    final atoms = <String>[];
    int offset = 0;
    while (offset + 8 <= bytes.length && atoms.length < 12) {
      final size = bytes.buffer.asByteData(offset, 4).getUint32(0);
      if (size < 8) break;
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      atoms.add(type);
      if (size == 0) break; // rest of file
      offset += size;
    }
    return atoms;
  }

  Future<void> _downloadLocal() async {
    if (_triedLocal) return; // only attempt once
    _triedLocal = true;
    try {
      final resp = await http.get(Uri.parse(widget.url)).timeout(const Duration(seconds: 20));
      if (resp.statusCode >= 200 && resp.statusCode < 400) {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/vid_${DateTime.now().millisecondsSinceEpoch}.mp4');
        await f.writeAsBytes(resp.bodyBytes);
        _localFile = f;
      }
    } catch (e) {
      debugPrint('[InlineVideoPlayer] local download failed: $e');
    }
  }

  Future<void> _initHardwareController() async {
    if (_controller != null) return;
    final source = _localFile != null ? VideoPlayerController.file(_localFile!) : VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = source;
    try {
      source.addListener(() {
        if (!mounted) return;
        final v = source.value;
        if (v.hasError && !_error) {
          setState(() {
            _error = true;
            _errorMessage = v.errorDescription;
          });
        }
      });
      await source.initialize();
      await source.setLooping(true);
      setState(() { _init = true; });
      await source.play();
      WakelockHelper.acquire();
    } catch (e, st) {
      _log('hardware init failed: $e');
      _log(st.toString());
      setState(() { _error = true; _errorMessage = e.toString(); });
    }
  }

  Future<void> _initControllerSequence() async {
  setState(() { _loading = true; _error = false; _finalError = false; _errorMessage = null; });
    await _preflight();
    if (_error) { setState(() { _loading = false; }); return; }
    await _initHardwareController();
    if (_error && _localFile == null) {
      // Try local download then retry hardware
      await _downloadLocal();
      if (_localFile != null) {
        _error = false; _errorMessage = null; _controller = null; _init = false;
        await _initHardwareController();
      }
    }
    // If still error after local retry: trigger software fallback automatically once
    if (_error && !_softwareMode && !_autoSoftwareTried) {
      _autoSoftwareTried = true;
      debugPrint('[InlineVideoPlayer] auto-switching to software decode');
      await _startSoftwareFallback(forceDownloadFirst: true);
    }
    if (_error && (_softwareTried || _softwareMode)) {
      _finalError = true;
    }
    setState(() { _loading = false; });
  }

  Future<void> _startSoftwareFallback({bool forceDownloadFirst = false}) async {
    if (_softwareTried) return;
    _softwareTried = true;
    if (forceDownloadFirst && _localFile == null) {
      await _downloadLocal();
    }
    try {
      _log('starting software fallback (local=${_localFile != null})');
      _mkPlayer = mk.Player();
      await _mkPlayer!.open(mk.Media(_localFile?.path ?? widget.url));
      _mkVideoController = mkv.VideoController(_mkPlayer!);
      await _mkPlayer!.setPlaylistMode(mk.PlaylistMode.loop);
      setState(() { _softwareMode = true; _error = false; });
    } catch (e, st) {
      _log('software decode failed: $e');
      _log(st.toString());
      setState(() { _error = true; _errorMessage = 'Software decode failed'; });
    }
  }

  void _togglePlay() {
    if (_softwareMode) {
      if (_mkPlayer == null) return;
      final playing = _mkPlayer!.state.playing;
      _mkPlayer!.setRate(1.0); // ensure normal rate
      _mkPlayer!.playOrPause();
      if (playing) {
        WakelockHelper.release();
      } else {
        WakelockHelper.acquire();
      }
      setState(() {});
    } else if (_controller != null) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        WakelockHelper.release();
      } else {
        _controller!.play();
        WakelockHelper.acquire();
      }
      setState(() {});
    }
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    _controller?.dispose();
  // media_kit_video's VideoController does not expose dispose; rely on player dispose
    _mkPlayer?.dispose();
    WakelockHelper.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_showControls && DateTime.now().difference(_lastInteraction) > _controlsVisibleDuration) {
      _showControls = false;
    }
    final aspect = !_softwareMode && _init && _controller != null && _controller!.value.aspectRatio > 0
        ? _controller!.value.aspectRatio
        : 16 / 9;
    return GestureDetector(
      onTap: () {
  // If the controller hasn't initialized yet (null) and we're not already in software mode or loading, start initialization.
  if (_controller == null && !_softwareMode && !_loading) {
          _initControllerSequence();
        } else {
          setState(() {
            _showControls = !_showControls;
            if (_showControls) _scheduleAutoHide();
          });
        }
      },
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_error && _finalError)
              Container(
                color: Colors.black26,
                alignment: Alignment.center,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 44),
                      const SizedBox(height: 8),
                      Text('Video failed', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, color: Colors.white)),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 6),
                        Text(_errorMessage!, style: const TextStyle(color: Colors.white70, fontSize: 12), textAlign: TextAlign.center),
                      ],
                      if (_preflightInfo != null) ...[
                        const SizedBox(height: 4),
                        Text(_preflightInfo!, style: const TextStyle(color: Colors.white54, fontSize: 10), textAlign: TextAlign.center),
                      ],
                      if (_showDetails) ...[
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 140, maxWidth: 360),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(6)),
                          child: SingleChildScrollView(
                            child: Text(_logLines.join('\n'), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () {
                              setState(() {
                                _error = false; _finalError = false; _errorMessage = null; _controller = null; _init = false; _preflightInfo = null; _softwareMode = false; _mkPlayer?.dispose(); _mkPlayer = null; _mkVideoController = null;
                              });
                              _initControllerSequence();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final uri = Uri.parse(widget.url);
                              try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {}
                            },
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open'),
                          ),
                          if (!_softwareMode && !_softwareTried)
                            TextButton.icon(
                              onPressed: _startSoftwareFallback,
                              icon: const Icon(Icons.memory),
                              label: const Text('Software decode'),
                            ),
                          TextButton.icon(
                            onPressed: () => setState(() => _showDetails = !_showDetails),
                            icon: Icon(_showDetails ? Icons.visibility_off : Icons.visibility, size: 18),
                            label: Text(_showDetails ? 'Hide details' : 'Details'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else if (_softwareMode && _mkVideoController != null) ...[
              mkv.Video(controller: _mkVideoController!),
            ] else if (_init && _controller != null) ...[
              VideoPlayer(_controller!),
            ] else ...[
              Stack(
                fit: StackFit.expand,
                children: [
                  if (_thumb != null) Image.memory(_thumb!, fit: BoxFit.cover) else Container(color: Colors.black12),
                  Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    alignment: Alignment.center,
                    child: _loading ? const CircularProgressIndicator() : const Icon(Icons.play_circle_outline, size: 64, color: Colors.white70),
                  ),
                ],
              ),
            ],
            if (_showControls && !(_error && _finalError))
              Positioned(
                bottom: 24, // raised from 8 to give extra space below controls
                left: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                    IconButton(
                      icon: Icon(
                        (_softwareMode ? (_mkPlayer?.state.playing ?? false) : (_controller?.value.isPlaying ?? false))
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: _togglePlay,
                    ),
                    if (!_softwareMode && _controller != null)
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(trackHeight: 2),
                          child: Slider(
                            value: _controller!.value.duration.inMilliseconds == 0
                                ? 0
                                : _controller!.value.position.inMilliseconds
                                    .clamp(0, _controller!.value.duration.inMilliseconds)
                                    .toDouble(),
                            max: _controller!.value.duration.inMilliseconds == 0
                                ? 1
                                : _controller!.value.duration.inMilliseconds.toDouble(),
                            onChanged: (v) async {
                              if (_controller == null) return;
                              final target = Duration(milliseconds: v.toInt());
                              await _controller!.seekTo(target);
                              _scheduleAutoHide();
                            },
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up, color: Colors.white),
                      tooltip: _muted ? 'Unmute' : 'Mute',
                      onPressed: () async {
                        if (_softwareMode) {
                          if (_mkPlayer == null) return;
                          _muted = !_muted;
                          await _mkPlayer!.setVolume(_muted ? 0 : 1.0);
                        } else if (_controller != null) {
                          _muted = !_muted;
                          await _controller!.setVolume(_muted ? 0 : 1);
                        }
                        setState(() {});
                        _scheduleAutoHide();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
                      tooltip: 'Mini player',
                      onPressed: () {
                        ref.read(miniVideoProvider.notifier).show(widget.url, title: widget.title);
                        if (!_softwareMode && _controller != null && _controller!.value.isPlaying) {
                          _controller!.pause();
                          WakelockHelper.release();
                        } else if (_softwareMode && (_mkPlayer?.state.playing ?? false)) {
                          _mkPlayer!.pause();
                          WakelockHelper.release();
                        }
                      },
                    ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Body scaffolding (overview removed) ----------------

class _UserBody extends ConsumerWidget {
  final int tab;
  final List<String> titles;
  final bool isBasicUser;
  const _UserBody({required this.tab, required this.titles, required this.isBasicUser});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = titles[tab];
    switch (current) {
      case 'Feed':
        return const _FeedSection();
      case 'Consult':
        return const _ConsultTab();
      case 'Requests':
        return const Center(child: Text('Requests coming soon'));
      case 'History':
        return const Center(child: Text('History coming soon'));
      case 'Profile':
        return const Center(child: Text('Profile coming soon'));
      default:
        return const Center(child: Text('Coming soon'));
    }
  }
}


// Dynamic side nav that reflects filtered titles for roles
class _UserSideNavDynamic extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<String> titles;
  const _UserSideNavDynamic({required this.currentIndex, required this.onSelect, required this.titles});
  @override
  Widget build(BuildContext context) {
    final items = <_SideItem>[];
    for (final t in titles) {
      switch (t) {
        case 'Feed': items.add(_SideItem(Icons.dynamic_feed_outlined, 'Feed')); break;
        case 'Consult': items.add(_SideItem(Icons.forum_outlined, 'Consult')); break;
        case 'Requests': items.add(_SideItem(Icons.build_outlined, 'Requests')); break;
        case 'History': items.add(_SideItem(Icons.history, 'History')); break;
        case 'Profile': items.add(_SideItem(Icons.person_outline, 'Profile')); break;
      }
    }
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
              child: Text('Menu', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
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


class _NewRequestDialog extends ConsumerStatefulWidget {
  const _NewRequestDialog();
  @override
  ConsumerState<_NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends ConsumerState<_NewRequestDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  String? _equipmentId;
  String? _equipmentName;

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Repair Request'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Describe the issue'),
              minLines: 2,
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a description' : null,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final picked = await showDialog<({String id, String name})>(context: context, builder: (_) => const _EquipmentPickerDialog());
                  if (picked != null) {
                    setState(() {
                      _equipmentId = picked.id;
                      _equipmentName = picked.name;
                    });
                  }
                },
                icon: const Icon(Icons.precision_manufacturing_outlined),
                label: Text(_equipmentName == null ? 'Select Equipment (optional)' : 'Selected: $_equipmentName'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            if (!_formKey.currentState!.validate()) return;
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            try {
              await ref.read(repairRequestsRepositoryProvider).create(
                    equipmentId: _equipmentId ?? '',
                    reportedByUserId: user.uid,
                    description: _descCtrl.text.trim(),
                  );
              if (!context.mounted) return;
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              navigator.pop();
              messenger.showSnackBar(const SnackBar(content: Text('Request created')));
            } catch (e) {
              if (!context.mounted) return;
              showFriendlyError(context, e, fallback: 'Could not submit.');
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EquipmentPickerDialog extends ConsumerStatefulWidget {
  const _EquipmentPickerDialog();
  @override
  ConsumerState<_EquipmentPickerDialog> createState() => _EquipmentPickerDialogState();
}

class _EquipmentPickerDialogState extends ConsumerState<_EquipmentPickerDialog> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(equipmentListProvider);
    return AlertDialog(
      title: const Text('Select Equipment'),
      content: LayoutBuilder(builder: (ctx, constraints) {
        final screenW = MediaQuery.of(ctx).size.width;
        final dialogW = screenW > 560 ? 520.0 : (screenW - 40).clamp(280.0, 520.0);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogW),
          child: SizedBox(
            width: dialogW,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 360,
                  child: list.when(
                    data: (items) {
                      final f = _q.isEmpty
                          ? items
                          : items.where((e) => e.name.toLowerCase().contains(_q) || e.model.toLowerCase().contains(_q) || e.manufacturer.toLowerCase().contains(_q)).toList();
                      if (f.isEmpty) return const Center(child: Text('No results'));
                      return ListView.separated(
                        itemCount: f.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final e = f[i];
                          return ListTile(
                            leading: const Icon(Icons.precision_manufacturing_outlined),
                            title: Text(e.name),
                            subtitle: Text('${e.manufacturer} • ${e.model}'),
                            onTap: () => Navigator.of(context).pop((id: e.id, name: e.name)),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => const Center(child: Text('Couldn’t load details')),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
      ],
    );
  }
}

// (Removed obsolete _TaskTile implementation remnants)


class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _EmptyState({required this.icon, required this.title, required this.message});
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

class _ProfileMenu extends ConsumerWidget {
  const _ProfileMenu();
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

// Dedicated header bar for User dashboard
class _UserHeaderBar extends StatelessWidget {
  final String title;
  final bool showMenu;
  final VoidCallback? onConsultTap; // new callback to switch tab
  const _UserHeaderBar({required this.title, this.showMenu = false, this.onConsultTap});
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
            Text('MedEquip', style: GoogleFonts.montserrat(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primaryDark)),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.outline),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              veryNarrow ? title : 'User • $title',
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
            tooltip: 'Consult Engineer',
            onPressed: onConsultTap,
            icon: const Icon(Icons.forum_outlined),
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
          const _ProfileMenu(),
        ],
      ),
    );
  }
}


class _SideItem {
  final IconData icon;
  final String label;
  const _SideItem(this.icon, this.label);
}

// ---------------- Consult Tab (new feature scaffold) ----------------
class _ConsultTab extends ConsumerWidget {
  const _ConsultTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleAsync = ref.watch(userRoleProvider);
    final role = roleAsync.value;
    final isEngineer = role == 'engineer' || role == 'admin';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text('Sign in required'));
    }
    final userConsults = ref.watch(userConsultsProvider);
    final openConsults = isEngineer ? ref.watch(openConsultsProvider) : const AsyncValue<List<ConsultRequest>>.data(<ConsultRequest>[]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Consult an Engineer', style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 18, color: AppColors.primaryDark)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const _NewConsultDialog()),
                icon: const Icon(Icons.forum_outlined, size: 18),
                label: const Text('New Consult'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final wide = constraints.maxWidth > 1100 && isEngineer;
                if (wide) {
                  // Two-column view: left user consults, right open pool (engineer)
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _ConsultListSection(title: 'My Consults', async: userConsults, emptyMessage: 'You have not asked any questions yet. Tap New Consult.')),
                      const SizedBox(width: 24),
                      if (isEngineer)
                        Expanded(child: _ConsultListSection(title: 'Open / Active', async: openConsults, engineer: true, emptyMessage: 'No open consults right now.')),
                    ],
                  );
                }
                // Stacked view
                return ListView(
                  children: [
                    _ConsultListSection(title: 'My Consults', async: userConsults, emptyMessage: 'You have not asked any questions yet. Tap New Consult.'),
                    if (isEngineer) ...[
                      const SizedBox(height: 32),
                      _ConsultListSection(title: 'Open / Active', async: openConsults, engineer: true, emptyMessage: 'No open consults right now.'),
                    ],
                    const SizedBox(height: 40),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsultListSection extends ConsumerWidget {
  final String title;
  final AsyncValue<List<ConsultRequest>> async;
  final bool engineer;
  final String emptyMessage;
  const _ConsultListSection({required this.title, required this.async, this.engineer = false, required this.emptyMessage});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingId = ref.watch(pendingConsultNavigationProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title, style: GoogleFonts.montserrat(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.primaryDark)),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: async.when(
            data: (items) {
              if (items.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.outline),
                    borderRadius: BorderRadius.circular(14),
                    color: Colors.white,
                  ),
                  child: Center(
                    child: Text(emptyMessage, style: const TextStyle(color: Colors.black54)),
                  ),
                );
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (pendingId != null) {
                  final idx = items.indexWhere((c) => c.id == pendingId);
                  if (idx >= 0) {
                    // Attempt to scroll the closest Scrollable ancestor
                    final ctx = _ConsultCard.globalKeyFor(items[idx].id).currentContext;
                    if (ctx != null) {
                      Scrollable.ensureVisible(
                        ctx,
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                      ref.read(pendingConsultNavigationProvider.notifier).clear();
                    }
                  }
                }
              });
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final parentState = context.findAncestorStateOfType<_UserDashboardScreenState>();
                  final highlightExpiry = parentState?._highlightExpiresAt;
                  final highlightActive = pendingId != null && items[i].id == pendingId && (highlightExpiry == null || DateTime.now().isBefore(highlightExpiry));
                  return _ConsultCard(item: items[i], engineer: engineer, highlight: highlightActive);
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) {
              final msg = e.toString();
              final isPerm = msg.contains('PERMISSION_DENIED') || msg.contains('permission-denied');
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: _ErrorInline(
                  message: isPerm
                      ? 'No permission to load consults. Ensure Firestore rules deployed and your role/claims are up to date.'
                      : 'Failed to load: $e',
                  onRetry: () {},
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ConsultCard extends ConsumerWidget {
  final ConsultRequest item;
  final bool engineer;
  final bool highlight;
  const _ConsultCard({required this.item, this.engineer = false, this.highlight = false});
  static GlobalKey globalKeyFor(String id) => GlobalObjectKey('_user_consult_$id');

  Color _statusColor(String s) {
    switch (s) {
      case 'open': return Colors.orange.shade600;
      case 'claimed': return Colors.amber.shade800;
      case 'answered': return Colors.green.shade600;
      case 'closed': return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final isClaimer = user != null && item.claimedBy == user.uid;
    final repo = ref.read(consultRepositoryProvider);
    final key = globalKeyFor(item.id);
    return AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: highlight ? Colors.yellow.shade50 : Colors.white,
        borderRadius: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)).borderRadius,
        border: Border.all(color: highlight ? Colors.amber.shade400 : AppColors.outline, width: highlight ? 2 : 1),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(item.status).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.status == 'answered'
                            ? Icons.check_circle_outline
                            : item.status == 'claimed'
                                ? Icons.handshake_outlined
                                : Icons.hourglass_bottom_outlined,
                        size: 16,
                        color: _statusColor(item.status),
                      ),
                      const SizedBox(width: 6),
                      Text(item.status.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _statusColor(item.status))),
                    ],
                  ),
                ),
                const Spacer(),
                // createdAt already a DateTime (from model mapping); no toDate() needed
                Text(_relativeTime(item.createdAt), style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 10),
            Text(item.question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            if (item.answer != null && item.answer!.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  border: Border.all(color: Colors.green.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.engineering_outlined, size: 18, color: Colors.green),
                    const SizedBox(width: 10),
                    Expanded(child: Text(item.answer!, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (engineer && item.status == 'open')
                  FilledButton(
                    onPressed: user == null ? null : () async { await repo.claim(item.id, user.uid); },
                    style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                    child: const Text('Claim'),
                  ),
                if (engineer && isClaimer && item.status == 'claimed')
                  FilledButton(
                    onPressed: () async {
                      final answer = await showDialog<String>(context: context, builder: (_) => const _AnswerConsultDialog());
                      if (answer != null && answer.trim().isNotEmpty) {
                        await repo.answer(item.id, user.uid, answer.trim());
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                    child: const Text('Answer'),
                  ),
                if (engineer && isClaimer && item.status == 'answered')
                  OutlinedButton(
                    onPressed: () async { await repo.close(item.id); },
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
                    child: const Text('Close'),
                  ),
                if (!engineer && item.status == 'answered')
                  TextButton(
                    onPressed: () async { await repo.close(item.id); },
                    child: const Text('Mark Closed'),
                  ),
                const Spacer(),
                if (item.claimedBy != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.engineering_outlined, size: 16, color: Colors.black54),
                      const SizedBox(width: 4),
                      Text(item.claimedBy == user?.uid ? 'You' : 'Engineer', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewConsultDialog extends ConsumerStatefulWidget {
  const _NewConsultDialog();
  @override
  ConsumerState<_NewConsultDialog> createState() => _NewConsultDialogState();
}

class _NewConsultDialogState extends ConsumerState<_NewConsultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qCtrl = TextEditingController();
  bool _submitting = false;
  @override
  void dispose() { _qCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Consult'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: TextFormField(
            controller: _qCtrl,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'What is your question?', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a question' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : () async {
            if (!_formKey.currentState!.validate()) return;
            setState(() => _submitting = true);
            try {
              await ref.read(consultRepositoryProvider).createConsult(question: _qCtrl.text);
              if (context.mounted) Navigator.of(context).pop();
            } catch (e) {
              if (context.mounted) showFriendlyError(context, e, fallback: 'Could not submit question');
            } finally {
              if (mounted) setState(() => _submitting = false);
            }
          },
          child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit'),
        ),
      ],
    );
  }
}

class _AnswerConsultDialog extends StatefulWidget {
  const _AnswerConsultDialog();
  @override
  State<_AnswerConsultDialog> createState() => _AnswerConsultDialogState();
}

class _AnswerConsultDialogState extends State<_AnswerConsultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _aCtrl = TextEditingController();
  bool _sending = false;
  @override
  void dispose() { _aCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Answer Consult'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 460,
          child: TextFormField(
            controller: _aCtrl,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(labelText: 'Type your answer', border: OutlineInputBorder()),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Answer required' : null,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _sending ? null : () {
            if (!_formKey.currentState!.validate()) return;
            setState(() => _sending = true);
            final answer = _aCtrl.text.trim();
            Navigator.of(context).pop(answer);
          },
          child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Send'),
        ),
      ],
    );
  }
}

// ---------------- Feed UI (reintegration) ----------------

class _FeedSection extends ConsumerStatefulWidget {
  const _FeedSection();
  @override
  ConsumerState<_FeedSection> createState() => _FeedSectionState();
}

class _FeedSectionState extends ConsumerState<_FeedSection> {
  final _scrollCtrl = ScrollController();
  int _unseen = 0;
  List<String> _knownTopIds = [];
  int _pendingNewCount = 0; // raw count before debounce commit
  bool _bannerVisible = true;
  Timer? _debounceTimer;
  Timer? _autoHideTimer;
  double _pulseScale = 1.0;
  int _lastDisplayedCount = 0;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels > (_scrollCtrl.position.maxScrollExtent - 400)) {
      ref.read(paginatedFeedProvider.notifier).loadMore();
    }
    // If user scrolls near top and we have unseen, auto-show banner but don't reset until refresh.
  }

  void _computeUnseen(List<Post> head, List<Post> current) {
    if (current.isEmpty) return; // already handled by empty state
    final topCurrentId = current.first.id;
    // If first id changed after reload, reset tracking.
    if (_knownTopIds.isEmpty || _knownTopIds.first != topCurrentId) {
      _knownTopIds = current.take(5).map((p) => p.id).toList();
    }
    // Count head posts not in current list's visible first segment.
    final currentIds = current.take(20).map((p) => p.id).toSet();
    final newOnTop = head.where((p) => !currentIds.contains(p.id)).length;
    _pendingNewCount = newOnTop;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (_unseen != _pendingNewCount) {
        _triggerCountChange(_pendingNewCount);
      }
    });
  }

  void _triggerCountChange(int value) {
    setState(() {
      _unseen = value;
      _bannerVisible = _unseen > 0;
      if (_unseen > 0 && _unseen > _lastDisplayedCount) {
        _pulseScale = 1.15; // start pulse
        // schedule scale reset
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return; setState(() => _pulseScale = 1.0);
        });
      }
      _lastDisplayedCount = _unseen;
    });
    _scheduleAutoHide();
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    if (_unseen == 0) return;
    // Only hide if user is near top (threshold 150px)
    if (_scrollCtrl.hasClients && _scrollCtrl.offset < 150) {
      _autoHideTimer = Timer(const Duration(seconds: 10), () {
        if (!mounted) return;
        if (_scrollCtrl.offset < 150) {
          setState(() => _bannerVisible = false);
        }
      });
    }
  }

  Future<void> _showNewPosts() async {
    // Optimistic prepend from head instead of full refresh.
    final headPosts = ref.read(feedHeadStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Post>[]);
    if (headPosts.isNotEmpty) {
      ref.read(paginatedFeedProvider.notifier).prependPosts(headPosts);
    }
    if (!mounted) return;
    setState(() { _unseen = 0; _bannerVisible = false; });
    // Scroll to top smoothly.
    await Future.delayed(const Duration(milliseconds: 20));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _debounceTimer?.cancel();
    _autoHideTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedState = ref.watch(paginatedFeedProvider);
    final head = ref.watch(feedHeadStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Post>[]);
    final notifier = ref.read(paginatedFeedProvider.notifier);

    if (!feedState.loadingInitial && feedState.posts.isNotEmpty) {
      _computeUnseen(head, feedState.posts);
    }

    // Filter posts locally if a query is present (case-insensitive) across title, authorHandle/authorName, and (if exists) caption/body fields.
    List<Post> visiblePosts = feedState.posts;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      visiblePosts = feedState.posts.where((p) {
        bool match(String? s) => s != null && s.toLowerCase().contains(q);
        return match(p.title) || match(p.authorHandle) || match(p.authorName) || match(p.caption) || match(p.equipmentName);
      }).toList();
    }

    Widget body;
    if (feedState.loadingInitial) {
      body = ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 32, top: 8),
        itemCount: 1 + 4, // search bar + skeletons
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildSearchBar(context);
          return const _PostSkeleton();
        },
      );
    } else if (feedState.errorMessage != null && feedState.posts.isEmpty) {
      body = ListView(
        controller: _scrollCtrl,
        children: [
          _buildSearchBar(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _ErrorInline(message: feedState.errorMessage!, onRetry: notifier.refresh),
          ),
        ],
      );
    } else if (feedState.posts.isEmpty) {
      body = ListView(
        controller: _scrollCtrl,
        children: [
          _buildSearchBar(context),
          const SizedBox(height: 60),
          const _EmptyState(icon: Icons.dynamic_feed_outlined, title: 'No posts yet', message: 'Posts you create or others share will appear here.'),
        ],
      );
    } else {
      final filtered = visiblePosts;
      body = ListView.separated(
        controller: _scrollCtrl,
        padding: const EdgeInsets.only(bottom: 90, top: 8),
        itemCount: 1 + filtered.length + (feedState.loadingMore || !feedState.reachedEnd ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (ctx, i) {
          if (i == 0) return _buildSearchBar(context);
          final contentIndex = i - 1;
          if (contentIndex >= filtered.length) {
            if (feedState.reachedEnd) return const SizedBox.shrink();
            if (feedState.errorMessage != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: _ErrorInline(message: feedState.errorMessage!, onRetry: notifier.loadMore),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5))),
            );
          }
          if (filtered.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: 80),
              child: _EmptyState(icon: Icons.search_off_outlined, title: 'No results', message: 'Try a different keyword.'),
            );
          }
          return _PostCard(post: filtered[contentIndex]);
        },
      );
    }

    return Stack(
      children: [
        RefreshIndicator(onRefresh: () async => notifier.refresh(), child: body),
        if (_unseen > 0 && _bannerVisible)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _showNewPosts,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  scale: _pulseScale,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0,3))],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fiber_new, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text('$_unseen new post${_unseen == 1 ? '' : 's'} – tap to load', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
  Widget _buildSearchBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Search posts…',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.outline)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.outline)),
        ),
      ),
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.outline)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _shimmerBox(width: 36, height: 36, shape: BoxShape.circle),
              const SizedBox(width: 12),
              Expanded(child: _shimmerBox(height: 14)),
              const SizedBox(width: 12),
              _shimmerBox(width: 24, height: 24, borderRadius: 8),
            ]),
            const SizedBox(height: 14),
            _shimmerBox(height: 12, width: 200),
            const SizedBox(height: 8),
            _shimmerBox(height: 12),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _shimmerBox(height: 170),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _shimmerBox(height: 10, width: 60),
              const Spacer(),
              _shimmerBox(height: 10, width: 40),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _shimmerBox({double? width, double? height, double borderRadius = 6, BoxShape shape = BoxShape.rectangle}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOut,
      width: width ?? double.infinity,
      height: height ?? 16,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class _PostCard extends ConsumerWidget {
  final Post post;
  const _PostCard({required this.post});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLiked = currentUser != null && post.likedBy.contains(currentUser.uid);
    final authorAsync = ref.watch(userByIdProvider(post.authorId));
    final authorDisplay = authorAsync.maybeWhen(
      data: (u) {
        // Preference order: user.username -> post.authorHandle -> lastName -> displayName -> email local-part
        String? localPart(String? e) => (e != null && e.contains('@')) ? e.split('@').first : e;
        return (u?.username?.isNotEmpty == true
                ? u!.username
                : (post.authorHandle?.isNotEmpty == true
                    ? post.authorHandle
                    : (u?.lastName.isNotEmpty == true
                        ? u!.lastName
                        : (u?.displayName.isNotEmpty == true
                            ? u!.displayName
                            : localPart(u?.email)))))
            ?? 'user';
      },
      orElse: () => post.authorHandle ?? post.authorName,
    );

    // Instagram-like layout:
    // 1. Header (avatar, username, optional title / equipment)
    // 2. Media (single video/manual tile OR swipe images)
    // 3. Action row (like, placeholder comment/share icons, save)
    // 4. Likes count
    // 5. Caption (username bold + text, expandable)
    // 6. Timestamp

    Widget buildMedia() {
      if (post.kind == 'video' && post.videoUrl != null) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: InlineVideoPlayer(url: post.videoUrl!, title: post.title ?? 'Video'),
        );
      }
      if (post.kind == 'manual' && post.fileUrl != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _ManualAttachmentTile(fileName: post.fileName ?? 'Manual', url: post.fileUrl!),
        );
      }
      if (post.imageUrls.length > 1) {
        return _ImageCarousel(urls: post.imageUrls);
      }
      if (post.imageUrls.isNotEmpty) {
        return AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(0),
            child: Image.network(post.imageUrls.first, fit: BoxFit.cover),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: () {},
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                  child: Text(
                    (authorDisplay.isNotEmpty ? authorDisplay.characters.first : '?').toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(authorDisplay, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (post.title != null && post.title!.trim().isNotEmpty)
                      Text(post.title!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.black54)),
                    if (post.equipmentName != null)
                      Text(post.equipmentName!, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ],
                ),
              ),
              IconButton(
                tooltip: isLiked ? 'Unlike' : 'Like',
                onPressed: currentUser == null
                    ? null
                    : () => ref.read(feedRepositoryProvider).toggleLike(postId: post.id, userId: currentUser.uid),
                icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.redAccent : Colors.black87),
              ),
            ],
          ),
        ),
        // Media
        buildMedia(),
        // Action Row (placeholder icons to match Instagram style)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              IconButton(
                icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border, color: isLiked ? Colors.redAccent : Colors.black87),
                splashRadius: 20,
                onPressed: currentUser == null
                    ? null
                    : () => ref.read(feedRepositoryProvider).toggleLike(postId: post.id, userId: currentUser.uid),
              ),
              IconButton(
                icon: const Icon(Icons.mode_comment_outlined),
                splashRadius: 20,
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.send_outlined),
                splashRadius: 20,
                onPressed: () {},
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.bookmark_border),
                splashRadius: 20,
                onPressed: () {},
              ),
            ],
          ),
        ),
        // Likes count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('${post.likeCount} likes', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        // Caption
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: _InstagramCaption(username: authorDisplay, text: post.caption),
          ),
        // Timestamp
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
          child: Text(_relativeTime(post.createdAt.toDate()).toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.black54, letterSpacing: 0.5)),
        ),
        const Divider(height: 0),
      ],
    );
  }
} // end _PostCard
// Instagram-style expandable caption widget
class _InstagramCaption extends StatefulWidget {
  final String username;
  final String text;
  const _InstagramCaption({required this.username, required this.text});
  @override
  State<_InstagramCaption> createState() => _InstagramCaptionState();
}

class _InstagramCaptionState extends State<_InstagramCaption> {
  bool _expanded = false;
  static const _maxChars = 140;
  @override
  Widget build(BuildContext context) {
    final needsTrim = widget.text.length > _maxChars;
    final display = !_expanded && needsTrim ? '${widget.text.substring(0, _maxChars).trimRight()}…' : widget.text;
    return GestureDetector(
      onTap: needsTrim ? () => setState(() => _expanded = !_expanded) : null,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.25),
          children: [
            TextSpan(text: widget.username, style: const TextStyle(fontWeight: FontWeight.w600)),
            const TextSpan(text: ' '),
            TextSpan(text: display),
            if (needsTrim)
              TextSpan(
                text: _expanded ? '  Show less' : '  More',
                style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }
}

class _ImageCarousel extends StatefulWidget {
  final List<String> urls;
  const _ImageCarousel({required this.urls});
  @override
  State<_ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<_ImageCarousel> {
  final PageController _pageCtrl = PageController();
  int _index = 0;
  @override
  void dispose() { _pageCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Image.network(widget.urls[i], fit: BoxFit.cover),
          ),
        ),
        if (widget.urls.length > 1)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child: Text('${_index + 1}/${widget.urls.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          ),
      ],
    );
  }
}
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  final weeks = diff.inDays ~/ 7; if (weeks < 5) return '${weeks}w';
  final months = diff.inDays ~/ 30; if (months < 12) return '${months}mo';
  final years = diff.inDays ~/ 365; return '${years}y';
}


class _ManualAttachmentTile extends StatelessWidget {
  final String fileName; final String url; const _ManualAttachmentTile({required this.fileName, required this.url});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async { try { await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication); } catch (_) {} },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.outline),
          color: Colors.white,
        ),
        child: Row(children: [
          const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(child: Text(fileName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          const Icon(Icons.open_in_new, size: 18, color: Colors.black54),
        ]),
      ),
    );
  }
}
