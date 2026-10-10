import 'package:flutter/material.dart';

import '../domain/models.dart';

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, this.imageUrl, this.radius = 20});

  final Person person;
  final String? imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      foregroundImage: url == null ? null : NetworkImage(url),
      child: Text(person.initials, style: TextStyle(color: scheme.onPrimaryContainer, fontSize: radius * 0.8)),
    );
  }
}

/// Fecha legible según el idioma.
String formatWhen(BuildContext context, DateTime when) {
  final date = MaterialLocalizations.of(context).formatShortDate(when);
  return '$date · ${TimeOfDay.fromDateTime(when).format(context)}';
}
