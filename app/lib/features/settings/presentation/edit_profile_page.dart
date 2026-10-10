import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/media/api_image.dart';
import '../../../shared/media/photo_picker.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../data/account_api.dart';

/// Editar el perfil público: nombre, usuario, presentación, localidad,
/// foto y portada. No se piden datos sensibles (RUT, fecha de nacimiento,
/// género, dirección): la app no los necesita.
class EditProfilePage extends StatelessWidget {
  const EditProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsEditProfile)),
      body: ApiScope.of(context).isConfigured ? const _EditProfileBody() : const ServerNotConnectedView(),
    );
  }
}

class _EditProfileBody extends StatefulWidget {
  const _EditProfileBody();

  @override
  State<_EditProfileBody> createState() => _EditProfileBodyState();
}

class _EditProfileBodyState extends State<_EditProfileBody> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _location = TextEditingController();

  late AccountApi _api;
  MyProfile? _original;
  Object? _loadError;
  bool _saving = false;
  String? _usernameError;

  // Imagen nueva elegida (aún sin subir) o `removed` para quitarla.
  PickedPhoto? _newPhoto;
  PickedPhoto? _newBanner;
  bool _removePhoto = false;
  bool _removeBanner = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = AccountApi(ApiScope.of(context));
    if (_original == null && _loadError == null) _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.profile();
      if (!mounted) return;
      setState(() {
        _original = p;
        _name.text = p.fullName ?? '';
        _username.text = p.username ?? '';
        _bio.text = p.bio ?? '';
        _location.text = p.location ?? '';
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _bio.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool banner}) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      final photo = await PhotoPicker.pick();
      if (photo == null || !mounted) return;
      setState(() {
        if (banner) {
          _newBanner = photo;
          _removeBanner = false;
        } else {
          _newPhoto = photo;
          _removePhoto = false;
        }
      });
    } on UnsupportedPhotoException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.photoUnsupported)));
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() {
      _saving = true;
      _usernameError = null;
    });
    try {
      final fields = <String, Object?>{
        'fullName': _name.text.trim(),
        'username': _username.text.trim().isEmpty ? null : _username.text.trim().toLowerCase(),
        'bio': _bio.text.trim(),
        'location': _location.text.trim(),
      };
      final photo = _newPhoto;
      if (photo != null) {
        fields['photoAssetId'] = await _api.uploadImage('profile-photo', photo.bytes, photo.contentType);
      } else if (_removePhoto) {
        fields['photoAssetId'] = null;
      }
      final banner = _newBanner;
      if (banner != null) {
        fields['bannerAssetId'] = await _api.uploadImage('profile-banner', banner.bytes, banner.contentType);
      } else if (_removeBanner) {
        fields['bannerAssetId'] = null;
      }
      await _api.updateProfile(fields);
      messenger.showSnackBar(SnackBar(content: Text(l10n.profileSaved)));
      if (router.canPop()) router.pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'username_taken') {
        setState(() => _usernameError = l10n.usernameTaken);
      } else {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final original = _original;
    if (_loadError != null) {
      return ErrorView(
        message: _loadError is ApiException ? (_loadError! as ApiException).message : l10n.errorGeneric,
        onRetry: () {
          setState(() => _loadError = null);
          _load();
        },
      );
    }
    if (original == null) return const Center(child: CircularProgressIndicator());

    final client = _api.client;
    Widget? current(String? path) {
      if (path == null) return null;
      if (path.startsWith('/api/')) return ApiImage(api: client, path: path);
      return Image.network(path, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox.shrink());
    }

    final bannerPreview = _newBanner != null
        ? Image.memory(_newBanner!.bytes, fit: BoxFit.cover)
        : (_removeBanner ? null : current(original.banner));
    final photoPreview = _newPhoto != null
        ? Image.memory(_newPhoto!.bytes, fit: BoxFit.cover)
        : (_removePhoto ? null : current(original.photo));
    final scheme = Theme.of(context).colorScheme;

    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Portada
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 3,
                      child: ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: bannerPreview ?? Center(child: Icon(Icons.landscape_outlined, color: scheme.onSurfaceVariant)),
                      ),
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton.icon(
                        key: const Key('pick-banner'),
                        onPressed: _saving ? null : () => _pick(banner: true),
                        icon: const Icon(Icons.image_outlined),
                        label: Text(l10n.profileChangeBanner),
                      ),
                      if (bannerPreview != null)
                        TextButton(
                          onPressed: _saving ? null : () => setState(() {
                            _newBanner = null;
                            _removeBanner = true;
                          }),
                          child: Text(l10n.remove),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      ClipOval(
                        child: SizedBox.square(
                          dimension: 72,
                          child: ColoredBox(
                            color: scheme.primaryContainer,
                            child: photoPreview ?? Icon(Icons.person_outline, size: 36, color: scheme.onPrimaryContainer),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Wrap(
                          children: [
                            TextButton.icon(
                              key: const Key('pick-photo'),
                              onPressed: _saving ? null : () => _pick(banner: false),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(l10n.profileChangePhoto),
                            ),
                            if (photoPreview != null)
                              TextButton(
                                onPressed: _saving ? null : () => setState(() {
                                  _newPhoto = null;
                                  _removePhoto = true;
                                }),
                                child: Text(l10n.remove),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('profile-name'),
                    controller: _name,
                    maxLength: 120,
                    decoration: InputDecoration(labelText: l10n.profileFullName),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('profile-username'),
                    controller: _username,
                    maxLength: 30,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l10n.profileUsername,
                      prefixText: '@',
                      helperText: l10n.profileUsernameHint,
                      errorText: _usernameError,
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim().toLowerCase();
                      if (value.isEmpty) return null;
                      final ok = RegExp(r'^[a-z0-9][a-z0-9._]{1,28}[a-z0-9]$').hasMatch(value) &&
                          !RegExp(r'[._]{2}').hasMatch(value);
                      return ok ? null : l10n.profileUsernameInvalid;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('profile-bio'),
                    controller: _bio,
                    maxLength: 500,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(labelText: l10n.profileBio, alignLabelWithHint: true),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('profile-location'),
                    controller: _location,
                    maxLength: 120,
                    decoration: InputDecoration(labelText: l10n.profileLocation, hintText: 'Valdivia, Los Ríos'),
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.profileMinimalData, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('profile-save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check),
                    label: Text(l10n.save),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
