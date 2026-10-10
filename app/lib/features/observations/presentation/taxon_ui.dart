import 'package:flutter/material.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../shared/location/location_service.dart';
import '../domain/observation_models.dart';

/// Nombre, color e ícono de cada grupo taxonómico.
String groupLabel(AppLocalizations l, String group) => switch (group) {
      'aves' => l.groupAves,
      'mamiferos' => l.groupMamiferos,
      'anfibios' => l.groupAnfibios,
      'reptiles' => l.groupReptiles,
      'peces' => l.groupPeces,
      'insectos' => l.groupInsectos,
      'flora' => l.groupFlora,
      'funga' => l.groupFunga,
      _ => l.groupOtros,
    };

Color groupColor(String group) => switch (group) {
      'aves' => const Color(0xFF2F6F7E),
      'mamiferos' => const Color(0xFF8A5A2B),
      'anfibios' => const Color(0xFF5E8A2E),
      'reptiles' => const Color(0xFF9A7B2F),
      'peces' => const Color(0xFF3E7CB1),
      'insectos' => const Color(0xFFB7892A),
      'flora' => const Color(0xFF2E5B2A),
      'funga' => const Color(0xFF7A3E65),
      _ => const Color(0xFF5F6B5A),
    };

IconData groupIcon(String group) => switch (group) {
      'aves' => Icons.flutter_dash,
      'mamiferos' => Icons.pets,
      'anfibios' => Icons.water_drop_outlined,
      'reptiles' => Icons.egg_outlined,
      'peces' => Icons.set_meal_outlined,
      'insectos' => Icons.bug_report_outlined,
      'flora' => Icons.local_florist_outlined,
      'funga' => Icons.spa_outlined,
      _ => Icons.eco_outlined,
    };

String statusLabel(AppLocalizations l, String status) => switch (status) {
      'LC' => l.statusLC,
      'NT' => l.statusNT,
      'VU' => l.statusVU,
      'EN' => l.statusEN,
      'CR' => l.statusCR,
      'DD' => l.statusDD,
      _ => l.statusNE,
    };

/// Chip del estado de conservación, en rojo si está amenazada.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.species});

  final Species species;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final threatened = species.threatened;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(threatened ? Icons.warning_amber_rounded : Icons.shield_outlined, size: 16, color: threatened ? scheme.error : null),
      label: Text('${species.conservationStatus} · ${statusLabel(l, species.conservationStatus)}'),
      side: threatened ? BorderSide(color: scheme.error) : null,
    );
  }
}

/// Marcador redondo con el color e ícono del grupo.
class GroupDot extends StatelessWidget {
  const GroupDot({super.key, required this.group, this.size = 32, this.faded = false});

  final String group;
  final double size;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final color = groupColor(group);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: faded ? color.withValues(alpha: 0.55) : color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Icon(groupIcon(group), color: Colors.white, size: size * 0.55),
    );
  }
}

String formatObservedAt(BuildContext context, DateTime when) {
  final m = MaterialLocalizations.of(context);
  return '${m.formatMediumDate(when)} · ${m.formatTimeOfDay(TimeOfDay.fromDateTime(when), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
}

String locationProblemText(AppLocalizations l, Object error) => switch (error) {
      LocationException(problem: LocationProblem.serviceDisabled) => l.locationErrorDisabled,
      LocationException(problem: LocationProblem.denied) => l.locationErrorDenied,
      LocationException(problem: LocationProblem.deniedForever) => l.locationErrorDeniedForever,
      _ => l.locationErrorUnavailable,
    };
