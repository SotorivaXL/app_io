// lib/util/web_video_view_stub.dart
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

Widget buildWebVideoView({
  required String viewId,
  required Uint8List videoBytes,
  Uint8List? posterBytes,
  String? fileName,
}) => const SizedBox.shrink();

void disposeWebVideoView(String viewId) {}
void playWebVideoView(String viewId) {}
void pauseWebVideoView(String viewId) {}
