import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/location/location_service.dart';
import '../../../shared/map/map_tiles.dart';
import '../../../shared/widgets/server_required.dart';
import '../../auth/application/auth_controller.dart';
import '../../observations/data/observations_api.dart';
import '../../observations/domain/observation_models.dart';
import '../../observations/presentation/taxon_ui.dart';
import '../../settings/application/settings_controller.dart';
import '../../settings/data/settings_repository.dart';

/// Mapa de biodiversidad (lámina, pantallas 41–50): mapa real con las
/// observaciones de la zona visible, filtros por grupo y capas.
class BiodiversityMapPage extends StatefulWidget {
  const BiodiversityMapPage({super.key});

  @override
  State<BiodiversityMapPage> createState() => _BiodiversityMapPageState();
}

class _BiodiversityMapPageState extends State<BiodiversityMapPage> {
  final _map = MapController();
  late ObservationsApi _api;
  Timer? _debounce;
  bool _ready = false;
  int _seq = 0;

  late BaseMap _base = SettingsScope.settingsOf(context).mapBase == MapBasePreference.topo ? BaseMap.topo : BaseMap.streets;
  late bool _showObservations = SettingsScope.settingsOf(context).mapShowObservations;
  bool _onlyMine = false;
  late bool _showPlaces = SettingsScope.settingsOf(context).mapShowPlaces;
  String? _group;

  List<Observation> _observations = const [];
  List<Place> _places = const [];
  bool _loading = false;
  Object? _error;
  LatLng? _myLocation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = ObservationsApi(ApiScope.of(context));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _map.dispose();
    super.dispose();
  }

  GeoBounds get _bounds {
    final b = _map.camera.visibleBounds;
    return GeoBounds(b.west, b.south, b.east, b.north);
  }

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _load);
  }

  Future<void> _load() async {
    if (!_ready || !_api.isConfigured) return;
    final seq = ++_seq;
    final bounds = _bounds;
    final mine = _onlyMine ? AuthScope.read(context).user?.uid : null;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _showObservations ? _api.inBounds(bounds, group: _group, user: mine) : Future.value(const <Observation>[]),
        _showPlaces ? _api.places(bounds) : Future.value(const <Place>[]),
      ]);
      if (!mounted || seq != _seq) return;
      setState(() {
        _observations = results[0] as List<Observation>;
        _places = results[1] as List<Place>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _goToMyLocation() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fix = await LocationService.current();
      if (!mounted) return;
      final point = LatLng(fix.latitude, fix.longitude);
      setState(() => _myLocation = point);
      _map.move(point, 15);
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(locationProblemText(l10n, e))));
    }
  }

  void _newObservationAt(LatLng? point) {
    final p = point ?? _map.camera.center;
    context.push('/observations/new?lat=${p.latitude.toStringAsFixed(6)}&lng=${p.longitude.toStringAsFixed(6)}').then((_) {
      if (mounted) _load();
    });
  }

  void _showObservation(Observation o) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GroupDot(group: o.group, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.title(lang), style: Theme.of(sheet).textTheme.titleLarge),
                        if (o.species != null)
                          Text(o.species!.scientificName, style: const TextStyle(fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(formatObservedAt(sheet, o.observedAt)),
              Text(l10n.observedBy(o.owner.name)),
              if (o.count != null) Text(l10n.individualsCount(o.count!)),
              if (o.obscured && !o.isMine) ...[
                const SizedBox(height: 8),
                Row(children: [const Icon(Icons.shield_outlined, size: 18), const SizedBox(width: 6), Expanded(child: Text(l10n.obscuredExplain))]),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('open-observation'),
                onPressed: () {
                  Navigator.pop(sheet);
                  context.push('/observations/${o.id}').then((_) {
                    if (mounted) _load();
                  });
                },
                icon: const Icon(Icons.open_in_new),
                label: Text(l10n.viewDetails),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPlace(Place p) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.name, style: Theme.of(sheet).textTheme.titleLarge),
              if (p.description != null) ...[const SizedBox(height: 8), Text(p.description!)],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openLayers() async {
    final l10n = context.l10n;
    final signedIn = AuthScope.read(context).user != null;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, setLocal) {
          void update(VoidCallback change) {
            setState(change);
            setLocal(() {});
            _load();
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(l10n.mapBaseLayer, style: Theme.of(sheet).textTheme.titleSmall),
                  ),
                  RadioGroup<BaseMap>(
                    groupValue: _base,
                    onChanged: (v) => update(() => _base = v ?? _base),
                    child: Column(
                      children: [
                        RadioListTile<BaseMap>(value: BaseMap.streets, title: Text(l10n.mapBaseStreets)),
                        RadioListTile<BaseMap>(value: BaseMap.topo, title: Text(l10n.mapBaseTopo)),
                      ],
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    key: const Key('layer-observations'),
                    title: Text(l10n.mapLayerObservations),
                    value: _showObservations,
                    onChanged: (v) => update(() => _showObservations = v),
                  ),
                  if (signedIn)
                    SwitchListTile(
                      key: const Key('layer-mine'),
                      title: Text(l10n.mapLayerMine),
                      value: _onlyMine,
                      onChanged: _showObservations ? (v) => update(() => _onlyMine = v) : null,
                    ),
                  SwitchListTile(
                    key: const Key('layer-places'),
                    title: Text(l10n.mapLayerPlaces),
                    subtitle: _showPlaces && _places.isEmpty && _api.isConfigured ? Text(l10n.mapPlacesEmpty) : null,
                    value: _showPlaces,
                    onChanged: (v) => update(() => _showPlaces = v),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final obscured = _observations.where((o) => o.obscured && !o.isMine).toList();

    final map = FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: valdiviaCenter,
        initialZoom: 12,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onMapReady: () {
          _ready = true;
          _load();
        },
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture) _scheduleLoad();
        },
        onLongPress: (_, point) => _newObservationAt(point),
      ),
      children: [
        MapTiles.layer(_base),
        if (obscured.isNotEmpty)
          CircleLayer(
            circles: [
              for (final o in obscured)
                CircleMarker(
                  point: LatLng(o.latitude, o.longitude),
                  radius: 5500,
                  useRadiusInMeter: true,
                  color: groupColor(o.group).withValues(alpha: 0.12),
                  borderColor: groupColor(o.group).withValues(alpha: 0.6),
                  borderStrokeWidth: 1.5,
                ),
            ],
          ),
        if (_showPlaces)
          MarkerLayer(
            markers: [
              for (final p in _places)
                Marker(
                  point: LatLng(p.latitude, p.longitude),
                  width: 36,
                  height: 36,
                  child: Semantics(
                    button: true,
                    label: p.name,
                    child: GestureDetector(
                      onTap: () => _showPlace(p),
                      child: Icon(Icons.place, color: scheme.tertiary, size: 36),
                    ),
                  ),
                ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final o in _observations)
              Marker(
                key: ValueKey('obs-${o.id}'),
                point: LatLng(o.latitude, o.longitude),
                width: 34,
                height: 34,
                child: Semantics(
                  button: true,
                  label: o.title(Localizations.localeOf(context).languageCode),
                  child: GestureDetector(
                    onTap: () => _showObservation(o),
                    child: GroupDot(group: o.group, size: 30, faded: o.obscured && !o.isMine),
                  ),
                ),
              ),
            if (_myLocation != null)
              Marker(
                point: _myLocation!,
                width: 22,
                height: 22,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ],
        ),
        MapTiles.attribution(_base),
      ],
    );

    String status;
    if (!_api.isConfigured) {
      status = l10n.mapServerNotConnected;
    } else if (_error != null) {
      status = apiErrorText(context, _error);
    } else if (_observations.length >= ObservationsApi.mapLimit) {
      status = l10n.mapLimitReached(ObservationsApi.mapLimit);
    } else {
      status = l10n.mapZoneCount(_observations.length);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.moduleMap),
        actions: [
          IconButton(key: const Key('map-layers'), tooltip: l10n.mapLayers, icon: const Icon(Icons.layers_outlined), onPressed: _openLayers),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-observation'),
        onPressed: _api.isConfigured ? () => _newObservationAt(null) : null,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(l10n.newObservation),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: map),
          // Filtro por grupo.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Material(
              color: scheme.surface.withValues(alpha: 0.92),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  children: [
                    for (final g in [null, ...taxonGroups])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FilterChip(
                          key: Key('group-${g ?? 'all'}'),
                          avatar: g == null ? null : Icon(groupIcon(g), size: 18, color: groupColor(g)),
                          label: Text(g == null ? l10n.mapAllGroups : groupLabel(l10n, g)),
                          selected: _group == g,
                          showCheckmark: false,
                          onSelected: (_) {
                            setState(() => _group = g);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 64,
            child: FloatingActionButton.small(
              heroTag: 'my-location',
              tooltip: l10n.mapMyLocation,
              onPressed: _goToMyLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 16,
            right: 180,
            child: Semantics(
              liveRegion: true,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(20),
                color: scheme.surface,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      Flexible(child: Text(status, key: const Key('map-status'), maxLines: 2, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
