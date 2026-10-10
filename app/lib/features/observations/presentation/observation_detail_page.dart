import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_scope.dart';
import '../../../shared/map/map_tiles.dart';
import '../../../shared/media/api_image.dart';
import '../../../shared/widgets/server_required.dart';
import '../../../shared/widgets/state_views.dart';
import '../../social/presentation/person_avatar.dart';
import '../data/observations_api.dart';
import '../domain/observation_models.dart';
import 'taxon_ui.dart';

/// Ficha de una observación (lámina, pantallas 59–62).
class ObservationDetailPage extends StatefulWidget {
  const ObservationDetailPage({super.key, required this.observationId});

  final String observationId;

  @override
  State<ObservationDetailPage> createState() => _ObservationDetailPageState();
}

class _ObservationDetailPageState extends State<ObservationDetailPage> {
  late ObservationsApi _api;
  Observation? _obs;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _api.isConfigured) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api = ObservationsApi(ApiScope.of(context));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await _api.get(widget.observationId);
      if (mounted) {
        setState(() {
          _obs = o;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.deleteObservationConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _api.delete(widget.observationId);
      if (mounted) context.pop(true);
    } catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(apiErrorText(context, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final o = _obs;
    Widget body;
    if (!_api.isConfigured) {
      body = const ServerNotConnectedView();
    } else if (_loading) {
      body = const LoadingView();
    } else if (_error != null || o == null) {
      body = ErrorView(message: apiErrorText(context, _error), onRetry: _load);
    } else {
      body = _content(context, o);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(o?.title(Localizations.localeOf(context).languageCode) ?? l10n.observationsTitle),
        actions: [
          if (o != null && o.isMine) ...[
            IconButton(
              key: const Key('edit-observation'),
              tooltip: l10n.editObservation,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final changed = await context.push<bool>('/observations/${o.id}/edit');
                if (changed == true && mounted) _load();
              },
            ),
            IconButton(key: const Key('delete-observation'), tooltip: l10n.delete, icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ],
      ),
      body: body,
    );
  }

  Widget _content(BuildContext context, Observation o) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final species = o.species;
    final point = LatLng(o.latitude, o.longitude);
    final hidden = o.obscured && !o.isMine;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (o.photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(aspectRatio: 4 / 3, child: ApiImage(api: _api.client, path: o.photo!)),
              )
            else if (species?.illustration != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.asset(species!.illustration!, fit: BoxFit.cover, errorBuilder: (context, _, _) => const SizedBox.shrink()),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                GroupDot(group: o.group, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(o.title(lang), style: theme.textTheme.headlineSmall),
                      if (species != null) Text(species.scientificName, style: const TextStyle(fontStyle: FontStyle.italic)),
                      Text(groupLabel(l10n, o.group), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (o.visibility == 'private') Chip(label: Text(l10n.privateBadge)),
              ],
            ),
            if (species != null) ...[
              const SizedBox(height: 8),
              Text(l10n.conservationStatusLabel, style: theme.textTheme.labelMedium),
              Align(alignment: Alignment.centerLeft, child: StatusChip(species: species)),
            ],
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: Text(formatWhen(context, o.observedAt)),
              subtitle: o.count == null ? null : Text(l10n.individualsCount(o.count!)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: PersonAvatar(person: o.owner, imageUrl: _api.client.absolute(o.owner.photo)),
              title: Text(l10n.observedBy(o.owner.name)),
              onTap: o.isMine ? null : () => context.push('/people/${o.owner.id}'),
            ),
            if (o.notes != null && o.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(o.notes!, style: theme.textTheme.bodyLarge),
            ],
            const Divider(height: 24),
            Text(l10n.locationLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            if (hidden)
              Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text('${l10n.obscuredLocation}. ${l10n.obscuredExplain}', key: const Key('obscured-note'))),
                ],
              )
            else
              Text([
                if (o.locationName != null) o.locationName!,
                '${o.latitude.toStringAsFixed(5)}, ${o.longitude.toStringAsFixed(5)}',
                if (o.locationSource == 'gps' && o.accuracyM != null) l10n.locationFromGps(o.accuracyM!.round()),
                if (o.isMine && o.obscured) l10n.hideExactLocationBody,
              ].join(' · ')),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 220,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: hidden ? 10 : 14,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag | InteractiveFlag.doubleTapZoom),
                  ),
                  children: [
                    MapTiles.layer(BaseMap.streets),
                    if (hidden)
                      CircleLayer(circles: [
                        CircleMarker(
                          point: point,
                          radius: 5500,
                          useRadiusInMeter: true,
                          color: groupColor(o.group).withValues(alpha: 0.15),
                          borderColor: groupColor(o.group),
                          borderStrokeWidth: 2,
                        ),
                      ])
                    else
                      MarkerLayer(markers: [Marker(point: point, width: 34, height: 34, child: GroupDot(group: o.group, size: 30))]),
                    MapTiles.attribution(BaseMap.streets),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
