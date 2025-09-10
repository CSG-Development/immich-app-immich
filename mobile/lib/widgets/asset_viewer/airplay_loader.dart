import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_video_player/native_video_player.dart';
import 'package:path_provider/path_provider.dart';

class AirplayLoader extends StatefulWidget {
  const AirplayLoader({super.key});

  @override
  State<AirplayLoader> createState() => _AirplayLoaderState();
}

class _AirplayLoaderState extends State<AirplayLoader> {
  NativeVideoPlayerController? _controller;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      // Load the asset bytes
      final bytes = await rootBundle.load('assets/loading_circle_dots.mp4');
      // Write to a temp file because native_video_player requires a real file path
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/airplay_loader.mp4');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      setState(() => _tempPath = file.path);
    } catch (_) {
      // Fallback silently; UI will show a spinner
    }
  }

  void _onViewReady(NativeVideoPlayerController c) async {
    _controller = c;
    if (_tempPath == null) {
      return;
    }
    try {
      final src = await VideoSource.init(path: _tempPath!, type: VideoSourceType.file);
      await c.loadVideoSource(src);
      await c.setLoop(true);
      await c.setVolume(0);
      await c.play();
    } catch (_) {
      // Ignore loader errors
    }
  }

  @override
  void dispose() {
    _controller?.stop();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Maintain a square-ish smaller indicator centered
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _tempPath == null
              ? const ColoredBox(
                  color: Colors.transparent,
                  child: Center(child: CircularProgressIndicator()),
                )
              : NativeVideoPlayerView(onViewReady: _onViewReady),
        ),
      ),
    );
  }
}
