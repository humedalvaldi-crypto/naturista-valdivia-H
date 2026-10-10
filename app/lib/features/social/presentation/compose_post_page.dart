import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/media/photo_picker.dart';
import '../../../shared/widgets/server_required.dart';
import '../data/social_api.dart';

/// Nueva publicación (texto, lugar y visibilidad). Devuelve la publicación creada.
class ComposePostPage extends StatefulWidget {
  const ComposePostPage({super.key, this.communitySlug});

  final String? communitySlug;

  @override
  State<ComposePostPage> createState() => _ComposePostPageState();
}

class _ComposePostPageState extends State<ComposePostPage> {
  final _formKey = GlobalKey<FormState>();
  final _body = TextEditingController();
  final _place = TextEditingController();
  String _visibility = 'public';
  bool _sending = false;
  String? _error;
  PickedPhoto? _photo;

  Future<void> _pickPhoto() async {
    final l10n = context.l10n;
    try {
      final photo = await PhotoPicker.pick();
      if (photo != null && mounted) setState(() => _photo = photo);
    } on UnsupportedPhotoException {
      if (mounted) setState(() => _error = l10n.photoUnsupported);
    }
  }

  @override
  void dispose() {
    _body.dispose();
    _place.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending || !(_formKey.currentState?.validate() ?? false)) return;
    final api = SocialApi(ApiScope.of(context));
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final photo = _photo;
      // Primero se sube la foto (el servidor valida tipo y tamaño) y luego la publicación.
      final mediaId = photo == null ? null : await api.uploadImage(photo.bytes, photo.contentType);
      final post = await api.createPost(
        body: _body.text.trim(),
        visibility: _visibility,
        locationName: _place.text,
        communitySlug: widget.communitySlug,
        mediaAssetId: mediaId,
      );
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(l10n.postPublished)));
      context.pop(post);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = apiErrorText(context, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.composeTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                TextFormField(
                  key: const Key('compose-body'),
                  controller: _body,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 2000,
                  decoration: InputDecoration(hintText: l10n.composeHint),
                  validator: (v) => (v == null || v.trim().isEmpty) ? l10n.errorRequired : null,
                ),
                const SizedBox(height: 8),
                if (_photo case final photo?)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          photo.bytes,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          // Si la vista previa no se puede mostrar, el servidor igual valida el archivo.
                          errorBuilder: (context, _, _) => Container(
                            height: 220,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: Text(photo.name),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 6,
                        right: 6,
                        child: IconButton.filledTonal(
                          tooltip: l10n.removePhoto,
                          onPressed: _sending ? null : () => setState(() => _photo = null),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('compose-photo'),
                      onPressed: _sending ? null : _pickPhoto,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      label: Text(l10n.addPhoto),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _place,
                  maxLength: 120,
                  decoration: InputDecoration(labelText: l10n.composeLocation, prefixIcon: const Icon(Icons.place_outlined)),
                ),
                const SizedBox(height: 8),
                Text(l10n.visibilityLabel, style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: _visibility,
                  onChanged: (v) => setState(() => _visibility = v ?? 'public'),
                  child: Column(
                    children: [
                      RadioListTile<String>(value: 'public', title: Text(l10n.visibilityPublic)),
                      RadioListTile<String>(value: 'followers', title: Text(l10n.visibilityFollowers)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('compose-submit'),
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(l10n.newPost),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
