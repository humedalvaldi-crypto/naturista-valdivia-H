import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/branding/brand.dart';

/// Pantalla 1 de la lámina. Se muestra mientras Firebase restaura la sesión
/// guardada; el router sale de aquí en cuanto se conoce el estado.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.forestDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(size: 168),
              const SizedBox(height: 28),
              Text(
                l10n.appTitle,
                textAlign: TextAlign.center,
                style: text.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.splashTagline,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 40),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
