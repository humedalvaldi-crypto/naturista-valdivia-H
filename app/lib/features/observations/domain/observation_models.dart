// Modelos de especies, observaciones y lugares, tal como los entrega la API.
import '../../social/domain/models.dart';

DateTime _date(Object? v) => DateTime.tryParse(v as String? ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
double? _numOrNull(Object? v) => (v as num?)?.toDouble();

/// Grupos taxonómicos del catálogo (mismos códigos que el servidor).
const taxonGroups = ['aves', 'mamiferos', 'anfibios', 'reptiles', 'peces', 'insectos', 'flora', 'funga', 'otros'];

class Species {
  const Species({
    required this.id,
    required this.scientificName,
    required this.group,
    required this.conservationStatus,
    required this.sensitive,
    this.commonNameEs,
    this.commonNameEn,
    this.illustration,
  });

  factory Species.fromJson(Map<String, dynamic> j) => Species(
        id: j['id'] as String,
        scientificName: j['scientificName'] as String? ?? '',
        commonNameEs: j['commonNameEs'] as String?,
        commonNameEn: j['commonNameEn'] as String?,
        group: j['group'] as String? ?? 'otros',
        conservationStatus: j['conservationStatus'] as String? ?? 'NE',
        sensitive: j['sensitive'] as bool? ?? false,
        illustration: j['illustration'] as String?,
      );

  final String id;
  final String scientificName;
  final String? commonNameEs;
  final String? commonNameEn;
  final String group;
  final String conservationStatus;
  final bool sensitive;
  final String? illustration;

  String commonName(String languageCode) =>
      (languageCode == 'en' ? commonNameEn ?? commonNameEs : commonNameEs ?? commonNameEn) ?? scientificName;

  /// Amenazada según UICN (vulnerable, en peligro, en peligro crítico).
  bool get threatened => const {'VU', 'EN', 'CR'}.contains(conservationStatus);
}

class Observation {
  const Observation({
    required this.id,
    required this.owner,
    required this.observedAt,
    required this.latitude,
    required this.longitude,
    required this.obscured,
    required this.visibility,
    required this.isMine,
    this.species,
    this.taxonName,
    this.count,
    this.accuracyM,
    this.locationSource,
    this.locationName,
    this.geoprivacy,
    this.notes,
    this.photo,
    this.photoAssetId,
  });

  factory Observation.fromJson(Map<String, dynamic> j) {
    final photo = j['photo'] as String?;
    return Observation(
      id: j['id'] as String,
      owner: Person.fromJson(j['owner'] as Map<String, dynamic>),
      species: j['species'] == null ? null : Species.fromJson(j['species'] as Map<String, dynamic>),
      taxonName: j['taxonName'] as String?,
      count: (j['count'] as num?)?.toInt(),
      observedAt: _date(j['observedAt']),
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      accuracyM: _numOrNull(j['accuracyM']),
      locationSource: j['locationSource'] as String?,
      locationName: j['locationName'] as String?,
      obscured: j['obscured'] as bool? ?? false,
      geoprivacy: j['geoprivacy'] as String?,
      notes: j['notes'] as String?,
      photo: photo,
      photoAssetId: photo?.split('/').last,
      visibility: j['visibility'] as String? ?? 'public',
      isMine: j['isMine'] as bool? ?? false,
    );
  }

  final String id;
  final Person owner;
  final Species? species;
  final String? taxonName;
  final int? count;
  final DateTime observedAt;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final String? locationSource;
  final String? locationName;
  final bool obscured;
  final String? geoprivacy;
  final String? notes;
  final String? photo;
  final String? photoAssetId;
  final String visibility;
  final bool isMine;

  String title(String languageCode) => species?.commonName(languageCode) ?? taxonName ?? '—';
  String get group => species?.group ?? 'otros';
}

class Place {
  const Place({required this.id, required this.kind, required this.name, required this.latitude, required this.longitude, this.description});

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'other',
        name: j['name'] as String? ?? '',
        description: j['description'] as String?,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
      );

  final String id;
  final String kind;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
}

/// Rectángulo geográfico: oeste, sur, este, norte.
class GeoBounds {
  const GeoBounds(this.west, this.south, this.east, this.north);

  final double west;
  final double south;
  final double east;
  final double north;

  String get query => [west, south, east, north].map((v) => v.clamp(-180, 180).toStringAsFixed(5)).join(',');
}
