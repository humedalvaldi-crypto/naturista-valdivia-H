import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_client.dart';

/// Reproduce una nota de audio privada: pide a la API un enlace firmado
/// temporal (1 h) y lo reproduce; así no hace falta enviar el token al reproductor.
class AudioNotePlayer extends StatefulWidget {
  const AudioNotePlayer({super.key, required this.api, required this.mediaId, this.label, this.compact = false});

  final ApiClient api;
  final String mediaId;
  final String? label;
  final bool compact;

  /// Para pruebas: reemplaza la reproducción real.
  static Future<void> Function(String url)? playOverride;

  @override
  State<AudioNotePlayer> createState() => _AudioNotePlayerState();
}

class _AudioNotePlayerState extends State<AudioNotePlayer> {
  AudioPlayer? _player;
  bool _playing = false;
  bool _loading = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    if (_playing) {
      await _player?.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await widget.api.post('/media/${widget.mediaId}/link');
      final url = widget.api.absolute((res['data'] as Map<String, dynamic>)['url'] as String)!;
      final override = AudioNotePlayer.playOverride;
      if (override != null) {
        await override(url);
      } else {
        final p = _player ??= AudioPlayer()
          ..onPlayerComplete.listen((_) {
            if (mounted) setState(() => _playing = false);
          });
        await p.play(UrlSource(url));
      }
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.audioPlayError)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final icon = _loading
        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded);
    return IconButton.filledTonal(
      key: Key('play-${widget.mediaId}'),
      tooltip: _playing ? l10n.audioStop : l10n.audioPlay,
      onPressed: _loading ? null : _toggle,
      icon: icon,
    );
  }
}
