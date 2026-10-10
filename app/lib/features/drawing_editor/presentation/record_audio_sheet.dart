import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/media/audio_capture.dart';

/// Grabadora de notas de audio (máx. 3 minutos). Devuelve el audio y su nombre.
class RecordAudioSheet extends StatefulWidget {
  const RecordAudioSheet({super.key});

  static const maxDuration = Duration(minutes: 3);

  @override
  State<RecordAudioSheet> createState() => _RecordAudioSheetState();
}

class _RecordAudioSheetState extends State<RecordAudioSheet> {
  final _capture = AudioCapture.create();
  final _label = TextEditingController();
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _recording = false;
  RecordedAudio? _result;
  String? _error;

  @override
  void dispose() {
    _ticker?.cancel();
    if (_recording) unawaited(_capture.cancel());
    _capture.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = context.l10n;
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      await _capture.start();
    } on MicrophoneDeniedException {
      if (mounted) setState(() => _error = l10n.micDenied);
      return;
    } catch (_) {
      if (mounted) setState(() => _error = l10n.recordError);
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= RecordAudioSheet.maxDuration) _stop();
    });
  }

  Future<void> _stop() async {
    final l10n = context.l10n;
    _ticker?.cancel();
    _ticker = null;
    RecordedAudio? audio;
    try {
      audio = await _capture.stop();
    } catch (_) {
      audio = null;
    }
    if (!mounted) return;
    setState(() {
      _recording = false;
      _result = audio;
      if (audio == null) _error = l10n.recordError;
    });
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final result = _result;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.recordAudioTitle, style: theme.textTheme.titleLarge),
            Text(l10n.recordLimit, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Center(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _recording ? l10n.recordingTime(_fmt(_elapsed)) : (result != null ? _fmt(result.duration) : '0:00'),
                  key: const Key('record-time'),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                key: Key(_recording ? 'record-stop' : 'record-start'),
                style: _recording ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error) : null,
                onPressed: _recording ? _stop : _start,
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(_recording ? l10n.recordStop : (result != null ? l10n.recordAgain : l10n.recordStart)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              TextField(
                key: const Key('audio-label'),
                controller: _label,
                maxLength: 60,
                decoration: InputDecoration(labelText: l10n.audioLabelHint),
              ),
            ],
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                FilledButton(
                  key: const Key('record-save'),
                  onPressed: result == null || _recording ? null : () => Navigator.pop(context, (result, _label.text.trim())),
                  child: Text(l10n.recordSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
