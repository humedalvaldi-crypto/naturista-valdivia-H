import 'package:flutter/material.dart';

import '../../core/l10n/l10n.dart';
import '../../core/network/api_client.dart';
import '../branding/brand.dart';

/// Se muestra cuando la API no está configurada: explica la situación sin
/// inventar datos.
class ServerNotConnectedView extends StatelessWidget {
  const ServerNotConnectedView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FrogImage(FrogSticker.tired, size: 120),
              const SizedBox(height: 16),
              Text(l10n.serverNotConnectedTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(l10n.serverNotConnectedBody, style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensaje legible para un error de la API.
String apiErrorText(BuildContext context, Object? error) {
  if (error is ApiException && error.message.isNotEmpty) return error.message;
  return context.l10n.errorGeneric;
}
