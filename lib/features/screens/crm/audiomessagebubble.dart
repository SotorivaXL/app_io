import 'dart:convert';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class AudioMessageBubble extends StatefulWidget {
  final String base64Audio;

  const AudioMessageBubble({Key? key, required this.base64Audio}) : super(key: key);

  @override
  State<AudioMessageBubble> createState() => _AudioMessageBubbleState();
}

class _AudioMessageBubbleState extends State<AudioMessageBubble> {
  late AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _isPlaying = false;
  Uint8List? _audioBytes;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _audioBytes = base64Decode(widget.base64Audio);

    _player.onPlayerStateChanged.listen((state) {
      setState(() => _isPlaying = state == PlayerState.playing);
    });

    _player.onDurationChanged.listen((d) {
      setState(() => _duration = d);
    });

    _player.onPositionChanged.listen((p) {
      setState(() => _position = p);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPause() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play(BytesSource(_audioBytes!));
    }
  }

  String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
          onPressed: _togglePlayPause,
        ),
        Text(_format(_position)),
        Expanded(
          child: Slider(
            min: 0.0,
            max: _duration.inSeconds.toDouble(),
            value: _position.inSeconds.clamp(0, _duration.inSeconds).toDouble(),
            onChanged: (value) {
              _player.seek(Duration(seconds: value.toInt()));
            },
          ),
        ),
        Text(_format(_duration)),
      ],
    );
  }
}