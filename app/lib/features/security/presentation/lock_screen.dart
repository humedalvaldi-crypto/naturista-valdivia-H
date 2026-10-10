import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/branding/brand.dart';
import '../application/app_lock_controller.dart';
import '../data/biometric_auth.dart';

/// Tapa la app hasta desbloquear con huella o rostro. No muestra contenido
/// privado detrás. Siempre ofrece entrar con la cuenta como alternativa.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.controller});

  final AppLockController controller;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String? _message;

  @override
  void initState() {
    super.initState();
    // Se pide la huella una vez al aparecer; luego, con el botón.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (!mounted) return;
    final l10n = context.l10n;
    final result = await widget.controller.unlock(l10n.lockReason);
    if (!mounted) return;
    setState(() {
      _message = switch (result) {
        BiometricResult.success => null,
        BiometricResult.failed => l10n.lockFailed(AppLockController.maxFailures - widget.controller.failures),
        BiometricResult.cancelled => null,
        BiometricResult.lockedOut => l10n.lockLockedOut,
        BiometricResult.unavailable => l10n.lockUnavailable,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      key: const Key('lock-screen'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const FrogImage(FrogSticker.neutral, size: 110),
                  const SizedBox(height: 16),
                  Text(l10n.lockTitle, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(l10n.lockBody, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('lock-unlock'),
                    onPressed: widget.controller.busy ? null : _unlock,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(l10n.lockUnlock),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    key: const Key('lock-use-account'),
                    onPressed: widget.controller.usePrimaryAuth,
                    child: Text(l10n.lockUseAccount),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _message!,
                      key: const Key('lock-message'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
