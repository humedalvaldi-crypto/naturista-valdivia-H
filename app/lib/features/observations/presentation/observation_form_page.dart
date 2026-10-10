import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/location/location_service.dart';
import '../../../shared/map/map_tiles.dart';
import '../../../shared/media/api_image.dart';
import '../../../shared/media/photo_picker.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../settings/application/settings_controller.dart';
import '../data/observations_api.dart';
import '../domain/observation_models.dart';
import 'taxon_ui.dart';

/// Registrar o editar una observación (lámina, pantallas 51–58).
class ObservationFormPage extends StatefulWidget {
  const ObservationFormPage({super.key, this.observationId, this.initialLatitude, this.initialLongitude});

  /// Si se indica, se edita esa observación.
  final String? observationId;
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<ObservationFormPage> createState() => _ObservationFormPageState();
}

class _ObservationFormPageState extends State<ObservationFormPage> {
  late ObservationsApi _api;
  final _map = MapController();
  final _speciesText = TextEditingController();
  final _count = TextEditingController();
  final _placeName = TextEditingController();
  final _notes = TextEditingController();

  bool _loading = false;
  Object? _loadError;
  bool _saving = false;
  String? _error;

  Species? _species;
  List<Species> _results = const [];
  int _searchSeq = 0;
  DateTime _observedAt = DateTime.now();
  LatLng? _point;
  double? _accuracy;
  String _source = 'manual';
  bool _locating = false;
  late bool _hideLocation = SettingsScope.settingsOf(context).hideLocationByDefault;
  late bool _private = SettingsScope.settingsOf(context).observationsPrivate;
  PickedPhoto? _photo;
  String? _existingPhotoPath;
  String? _existingPhotoId;

  bool get _editing => widget.observationId != null;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _point = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_editing && mounted && _api.isConfigured) _loadExisting();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = ObservationsApi(ApiScope.of(context));
  }

  @override
  void dispose() {
    _map.dispose();
    _speciesText.dispose();
    _count.dispose();
    _placeName.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final o = await _api.get(widget.observationId!);
      if (!mounted) return;
      setState(() {
        _species = o.species;
        _speciesText.text = o.species == null ? o.taxonName ?? '' : '';
        _count.text = o.count?.toString() ?? '';
        _observedAt = o.observedAt;
        _point = LatLng(o.latitude, o.longitude);
        _accuracy = o.accuracyM;
        _source = o.locationSource ?? 'manual';
        _placeName.text = o.locationName ?? '';
        _hideLocation = o.geoprivacy == 'obscured';
        _private = o.visibility == 'private';
        _notes.text = o.notes ?? '';
        _existingPhotoPath = o.photo;
        _existingPhotoId = o.photoAssetId;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _search(String text) async {
    final seq = ++_searchSeq;
    final q = text.trim();
    if (q.length < 2) {
      setState(() => _results = const []);
      return;
    }
    try {
      final found = await _api.species(query: q);
      if (mounted && seq == _searchSeq) setState(() => _results = found.take(6).toList());
    } catch (_) {
      // Sin catálogo se puede seguir con el nombre libre.
      if (mounted && seq == _searchSeq) setState(() => _results = const []);
    }
  }

  void _chooseSpecies(Species s) {
    setState(() {
      _species = s;
      _results = const [];
      _speciesText.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _observedAt,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_observedAt));
    if (!mounted) return;
    final t = time ?? TimeOfDay.fromDateTime(_observedAt);
    setState(() => _observedAt = DateTime(date.year, date.month, date.day, t.hour, t.minute));
  }

  Future<void> _useGps() async {
    final l10n = context.l10n;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      final fix = await LocationService.current();
      if (!mounted) return;
      final p = LatLng(fix.latitude, fix.longitude);
      setState(() {
        _point = p;
        _accuracy = fix.accuracyM;
        _source = 'gps';
      });
      _moveMap(p);
    } catch (e) {
      if (mounted) setState(() => _error = locationProblemText(l10n, e));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// El minimapa puede no estar construido (fuera de pantalla): entonces no se mueve.
  void _moveMap(LatLng p) {
    try {
      _map.move(p, 15);
    } catch (_) {
      // Se ajusta al volver a mostrarse: el marcador ya tiene el punto nuevo.
    }
  }

  Future<void> _pickPhoto() async {
    final l10n = context.l10n;
    try {
      final photo = await PhotoPicker.pick();
      if (photo != null && mounted) setState(() => _photo = photo);
    } on UnsupportedPhotoException {
      if (mounted) setState(() => _error = l10n.photoUnsupported);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final free = _speciesText.text.trim();
    if (_species == null && free.isEmpty) {
      setState(() => _error = l10n.speciesRequired);
      return;
    }
    final point = _point;
    if (point == null) {
      setState(() => _error = l10n.locationRequired);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? photoId = _existingPhotoId;
      final photo = _photo;
      if (photo != null) photoId = await _api.uploadPhoto(photo.bytes, photo.contentType);
      final count = int.tryParse(_count.text.trim());
      final fields = <String, Object?>{
        'speciesId': _species?.id,
        'taxonName': _species == null ? free : null,
        'count': count != null && count > 0 ? count : null,
        'observedAt': _observedAt.toUtc().toIso8601String(),
        'latitude': double.parse(point.latitude.toStringAsFixed(6)),
        'longitude': double.parse(point.longitude.toStringAsFixed(6)),
        'accuracyM': _source == 'gps' ? _accuracy : null,
        'locationSource': _source,
        'locationName': _placeName.text.trim(),
        'geoprivacy': _hideLocation ? 'obscured' : 'open',
        'notes': _notes.text.trim(),
        'photoAssetId': photoId,
        'visibility': _private ? 'private' : 'public',
      };
      final saved = _editing ? await _api.update(widget.observationId!, fields) : await _api.create(fields);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.observationSaved)));
      if (_editing) {
        context.pop(true);
      } else {
        context.pushReplacement('/observations/${saved.id}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = apiErrorText(context, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = _editing ? l10n.editObservation : l10n.newObservation;
    if (!_api.isConfigured) return Scaffold(appBar: AppBar(title: Text(title)), body: const ServerNotConnectedView());
    if (_loading) return Scaffold(appBar: AppBar(title: Text(title)), body: const LoadingView());
    if (_loadError != null) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: ErrorView(message: apiErrorText(context, _loadError), onRetry: _loadExisting));
    }

    final lang = Localizations.localeOf(context).languageCode;
    final theme = Theme.of(context);
    final sensitive = _species?.sensitive ?? false;
    final free = _speciesText.text.trim();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            // Columna completa (no lista perezosa): así el minimapa no se
            // destruye ni se vuelve a crear con el mismo controlador al desplazarse.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Especie ──
                Text(l10n.speciesLabel, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_species != null)
                  Card(
                    child: ListTile(
                      key: const Key('selected-species'),
                      leading: GroupDot(group: _species!.group),
                      title: Text(_species!.commonName(lang)),
                      subtitle: Text(_species!.scientificName, style: const TextStyle(fontStyle: FontStyle.italic)),
                      trailing: IconButton(
                        tooltip: l10n.cancel,
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _species = null),
                      ),
                    ),
                  )
                else ...[
                  TextField(
                    key: const Key('species-field'),
                    controller: _speciesText,
                    textInputAction: TextInputAction.search,
                    maxLength: 120,
                    decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: l10n.speciesHint),
                    onChanged: _search,
                  ),
                  for (final s in _results)
                    ListTile(
                      key: Key('species-option-${s.id}'),
                      leading: GroupDot(group: s.group, size: 28),
                      title: Text(s.commonName(lang)),
                      subtitle: Text(s.scientificName, style: const TextStyle(fontStyle: FontStyle.italic)),
                      trailing: s.threatened ? Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error) : null,
                      onTap: () => _chooseSpecies(s),
                    ),
                  if (free.length >= 2 && _results.every((s) => s.commonName(lang).toLowerCase() != free.toLowerCase()))
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text(l10n.speciesFreeText(free), style: theme.textTheme.bodySmall),
                    ),
                ],
                if (_species != null) Align(alignment: Alignment.centerLeft, child: StatusChip(species: _species!)),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('count-field'),
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: l10n.countLabel),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(l10n.observedAtLabel),
                  subtitle: Text(formatObservedAt(context, _observedAt)),
                  onTap: _pickDateTime,
                ),
                const Divider(),

                // ── Ubicación ──
                Text(l10n.locationLabel, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 240,
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: _point ?? valdiviaCenter,
                        initialZoom: _point == null ? 11 : 15,
                        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                        onTap: (_, p) => setState(() {
                          _point = p;
                          _source = 'manual';
                          _accuracy = null;
                        }),
                      ),
                      children: [
                        MapTiles.layer(BaseMap.streets),
                        if (_point != null)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _point!,
                                width: 40,
                                height: 40,
                                alignment: Alignment.topCenter,
                                child: Icon(Icons.location_on, size: 40, color: theme.colorScheme.error),
                              ),
                            ],
                          ),
                        MapTiles.attribution(BaseMap.streets),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('use-gps'),
                      onPressed: _locating ? null : _useGps,
                      icon: _locating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location),
                      label: Text(l10n.useMyLocation),
                    ),
                    Text(
                      _point == null
                          ? l10n.locationTapHint
                          : '${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)} · '
                              '${_source == 'gps' && _accuracy != null ? l10n.locationFromGps(_accuracy!.round()) : l10n.locationManual}',
                      key: const Key('location-text'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: _placeName, maxLength: 120, decoration: InputDecoration(labelText: l10n.locationNameLabel)),
                SwitchListTile(
                  key: const Key('hide-location'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.hideExactLocation),
                  subtitle: Text(sensitive ? l10n.sensitiveSpeciesForced : l10n.hideExactLocationBody),
                  value: sensitive || _hideLocation,
                  onChanged: sensitive ? null : (v) => setState(() => _hideLocation = v),
                ),
                SwitchListTile(
                  key: const Key('private-observation'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.observationPrivate),
                  value: _private,
                  onChanged: (v) => setState(() => _private = v),
                ),
                const Divider(),

                // ── Foto y notas ──
                if (_photo != null)
                  _PhotoPreview(bytes: _photo!.bytes, name: _photo!.name, onRemove: () => setState(() => _photo = null))
                else if (_existingPhotoPath != null)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(height: 180, width: double.infinity, child: ApiImage(api: _api.client, path: _existingPhotoPath!)),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: IconButton.filledTonal(
                          tooltip: l10n.removePhoto,
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _existingPhotoPath = null;
                            _existingPhotoId = null;
                          }),
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    key: const Key('observation-photo'),
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: Text(l10n.addPhoto),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _notes,
                  minLines: 3,
                  maxLines: 8,
                  maxLength: 2000,
                  decoration: InputDecoration(labelText: l10n.notesLabel, alignLabelWithHint: true),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, key: const Key('form-error'), style: TextStyle(color: theme.colorScheme.error)),
                  ),
                FilledButton.icon(
                  key: const Key('save-observation'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(l10n.saveObservation),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.bytes, required this.name, required this.onRemove});

  final Uint8List bytes;
  final String name;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: SizedBox(
          width: 56,
          height: 56,
          child: Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (context, _, _) => const Icon(Icons.image_outlined)),
        ),
        title: Text(name, overflow: TextOverflow.ellipsis),
        trailing: IconButton(tooltip: context.l10n.removePhoto, icon: const Icon(Icons.close), onPressed: onRemove),
      ),
    );
  }
}
