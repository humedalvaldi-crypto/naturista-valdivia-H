import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/widgets/server_required.dart';
import '../data/social_api.dart';
import '../domain/models.dart';

/// Dirección pública de la app web. En la web se usa la dirección actual.
const _publicWebUrl = String.fromEnvironment(
  'PUBLIC_WEB_URL',
  defaultValue: 'https://humedalvaldi-crypto.github.io/naturista-valdivia-H/',
);

/// Enlace a una ruta de la app web (p. ej. `/posts/<id>`).
Uri appLink(String path) {
  final base = kIsWeb ? Uri.base.removeFragment() : Uri.parse(_publicWebUrl);
  return base.replace(fragment: path);
}

/// Enlace que abre la publicación en la app web (ruta `/posts/:id`).
Uri postLink(String postId) => appLink('/posts/$postId');

/// Enlace público de un cuaderno (ruta `/explore/notebooks/:id`). Solo abre si
/// el cuaderno es público o si quien lo abre es su dueña.
Uri notebookLink(String notebookId) => appLink('/explore/notebooks/$notebookId');

/// Comparte un enlace. Reemplazable en pruebas.
class LinkSharer {
  LinkSharer._();

  /// Devuelve true si el enlace se copió (para avisar), false si se abrió el
  /// menú de compartir del sistema.
  static Future<bool> Function(Uri link, String subject) share = _defaultShare;

  static Future<bool> _defaultShare(Uri link, String subject) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: link.toString()));
      return true;
    }
    await SharePlus.instance.share(ShareParams(text: link.toString(), subject: subject));
    return false;
  }
}

Future<void> sharePost(BuildContext context, Post post) => shareLink(context, postLink(post.id), post.author.name);

/// Comparte [link] con el menú del sistema (o lo copia en la web).
Future<void> shareLink(BuildContext context, Uri link, String subject) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  try {
    final copied = await LinkSharer.share(link, subject);
    if (copied) messenger.showSnackBar(SnackBar(content: Text(l10n.linkCopied)));
  } catch (_) {
    // Si el sistema no puede compartir, al menos se copia el enlace.
    await Clipboard.setData(ClipboardData(text: link.toString()));
    messenger.showSnackBar(SnackBar(content: Text(l10n.linkCopied)));
  }
}

/// Abre el editor de una publicación propia y guarda en el servidor.
/// Devuelve la versión guardada, o null si se canceló.
Future<Post?> editPost(BuildContext context, SocialApi api, Post post) {
  return showDialog<Post>(context: context, builder: (_) => _EditPostDialog(api: api, post: post));
}

class _EditPostDialog extends StatefulWidget {
  const _EditPostDialog({required this.api, required this.post});

  final SocialApi api;
  final Post post;

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final _body = TextEditingController(text: widget.post.body);
  late final _location = TextEditingController(text: widget.post.locationName ?? '');
  late String _visibility = widget.post.visibility == 'followers' ? 'followers' : 'public';
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _body.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) return;
    final p = widget.post;
    final location = _location.text.trim();
    final bodyChanged = body != p.body;
    final visibilityChanged = _visibility != p.visibility;
    final locationChanged = location != (p.locationName ?? '');
    if (!bodyChanged && !visibilityChanged && !locationChanged) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.api.updatePost(
        p.id,
        body: bodyChanged ? body : null,
        visibility: visibilityChanged ? _visibility : null,
        locationName: locationChanged ? location : null,
      );
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiErrorText(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.editPost),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('edit-post-body'),
              controller: _body,
              maxLength: 2000,
              minLines: 3,
              maxLines: 8,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: l10n.composeHint),
            ),
            TextField(
              key: const Key('edit-post-location'),
              controller: _location,
              maxLength: 120,
              decoration: InputDecoration(labelText: l10n.composeLocation),
            ),
            const SizedBox(height: 8),
            Text(l10n.visibilityLabel),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              key: const Key('edit-post-visibility'),
              segments: [
                ButtonSegment(value: 'public', label: Text(l10n.visibilityPublic)),
                ButtonSegment(value: 'followers', label: Text(l10n.visibilityFollowers)),
              ],
              selected: {_visibility},
              onSelectionChanged: (v) => setState(() => _visibility = v.first),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(
          key: const Key('edit-post-save'),
          onPressed: _saving || _body.text.trim().isEmpty ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
