import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'audio_bytes_io.dart' if (dart.library.js_interop) 'audio_bytes_web.dart' as bytes_impl;

/// Audio grabado: bytes y tipo real.
class RecordedAudio {
  const RecordedAudio({required this.bytes, required this.contentType, required this.duration});

  final Uint8List bytes;
  final String contentType;
  final Duration duration;
}

class MicrophoneDeniedException implements Exception {
  const MicrophoneDeniedException();
}

/// Tipo real del audio por sus primeros bytes (el servidor también lo comprueba).
String? sniffAudioType(Uint8List b) {
  if (b.length < 12) return null;
  if (b[0] == 0x1a && b[1] == 0x45 && b[2] == 0xdf && b[3] == 0xa3) return 'audio/webm';
  if (b[0] == 0x4f && b[1] == 0x67 && b[2] == 0x67 && b[3] == 0x53) return 'audio/ogg';
  if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) return 'audio/mp4';
  if ((b[0] == 0x49 && b[1] == 0x44 && b[2] == 0x33) || (b[0] == 0xff && (b[1] & 0xe0) == 0xe0)) return 'audio/mpeg';
  return null;
}

/// Grabación con el micrófono. Se puede reemplazar en pruebas.
abstract class AudioCapture {
  static AudioCapture Function() create = _DeviceAudioCapture.new;

  Future<void> start();
  Future<RecordedAudio?> stop();
  Future<void> cancel();
  void dispose();
}

class _DeviceAudioCapture implements AudioCapture {
  final _recorder = AudioRecorder();
  DateTime? _started;

  @override
  Future<void> start() async {
    if (!await _recorder.hasPermission()) throw const MicrophoneDeniedException();
    // Opus (WebM) en la web, AAC (M4A) en Android: ambos los acepta la API.
    final encoder = kIsWeb && await _recorder.isEncoderSupported(AudioEncoder.opus) ? AudioEncoder.opus : AudioEncoder.aacLc;
    final path = kIsWeb ? '' : '${(await getTemporaryDirectory()).path}/nota-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(RecordConfig(encoder: encoder, bitRate: 64000, numChannels: 1), path: path);
    _started = DateTime.now();
  }

  @override
  Future<RecordedAudio?> stop() async {
    final path = await _recorder.stop();
    final started = _started;
    _started = null;
    if (path == null || started == null) return null;
    final bytes = await bytes_impl.readRecording(path);
    final type = sniffAudioType(bytes);
    if (type == null) return null;
    return RecordedAudio(bytes: bytes, contentType: type, duration: DateTime.now().difference(started));
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    _started = null;
  }

  @override
  void dispose() => _recorder.dispose();
}
