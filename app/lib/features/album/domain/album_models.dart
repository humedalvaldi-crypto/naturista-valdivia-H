// Álbum de especies y logros, tal como los entrega GET /users/:id/album.
import '../../observations/domain/observation_models.dart';

class AlbumSpecies {
  const AlbumSpecies({required this.species, required this.unlocked, required this.observationCount, this.via, this.firstSeen});

  factory AlbumSpecies.fromJson(Map<String, dynamic> j) => AlbumSpecies(
        species: Species.fromJson(j),
        unlocked: j['unlocked'] as bool? ?? false,
        via: j['via'] as String?,
        firstSeen: DateTime.tryParse(j['firstSeen'] as String? ?? '')?.toLocal(),
        observationCount: (j['observationCount'] as num?)?.toInt() ?? 0,
      );

  final Species species;
  final bool unlocked;
  final String? via;
  final DateTime? firstSeen;
  final int observationCount;
}

class Achievement {
  const Achievement({required this.id, required this.target, required this.progress, required this.unlocked});

  factory Achievement.fromJson(Map<String, dynamic> j) => Achievement(
        id: j['id'] as String,
        target: (j['target'] as num?)?.toInt() ?? 1,
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        unlocked: j['unlocked'] as bool? ?? false,
      );

  final String id;
  final int target;
  final int progress;
  final bool unlocked;
}

class AlbumData {
  const AlbumData({required this.species, required this.achievements, required this.unlocked, required this.total});

  factory AlbumData.fromJson(Map<String, dynamic> j) {
    final stats = (j['stats'] as Map<String, dynamic>?) ?? const {};
    return AlbumData(
      species: ((j['species'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(AlbumSpecies.fromJson).toList(),
      achievements: ((j['achievements'] as List<dynamic>?) ?? const []).cast<Map<String, dynamic>>().map(Achievement.fromJson).toList(),
      unlocked: (stats['unlocked'] as num?)?.toInt() ?? 0,
      total: (stats['total'] as num?)?.toInt() ?? 0,
    );
  }

  final List<AlbumSpecies> species;
  final List<Achievement> achievements;
  final int unlocked;
  final int total;
}
