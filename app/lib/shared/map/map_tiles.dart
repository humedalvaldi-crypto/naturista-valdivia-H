import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

/// Centro de Valdivia: punto de partida del mapa.
const valdiviaCenter = LatLng(-39.8142, -73.2459);

enum BaseMap { streets, topo }

/// Mapas base reales con su atribución obligatoria.
/// En pruebas `enabled = false` evita pedir teselas por la red.
abstract final class MapTiles {
  static bool enabled = true;

  static const _userAgent = 'cl.naturistavaldivia.app';

  static Widget layer(BaseMap base) {
    if (!enabled) return const ColoredBox(color: Color(0xFFE8EFE4), child: SizedBox.expand());
    return switch (base) {
      BaseMap.streets => TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _userAgent,
          maxNativeZoom: 19,
        ),
      BaseMap.topo => TileLayer(
          urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
          userAgentPackageName: _userAgent,
          maxNativeZoom: 17,
        ),
    };
  }

  static Widget attribution(BaseMap base) => RichAttributionWidget(
        alignment: AttributionAlignment.bottomRight,
        attributions: [
          TextSourceAttribution(
            'OpenStreetMap contributors',
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
          ),
          if (base == BaseMap.topo)
            TextSourceAttribution(
              'OpenTopoMap (CC-BY-SA)',
              onTap: () => launchUrl(Uri.parse('https://opentopomap.org/about')),
            ),
        ],
      );
}
