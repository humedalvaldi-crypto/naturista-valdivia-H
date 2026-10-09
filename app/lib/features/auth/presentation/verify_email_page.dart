import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../application/auth_controller.dart';
import 'auth_widgets.dart';

/// Pantalla 24 de la lámina: Verificar correo. Solo para cuentas creadas con
/// correo y contraseña (las de Google ya vienen verificadas).
class VerifyEmailPage extends StatefulWidget {
  const VerifyEmailPage({super.key});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  String? _info;
  String? _error;

  Future<void> _check() async {
    final l10n = context.l10n;
    final auth = AuthScope.read(context);
    setState(() {
      _info = null;
      _error = null;
    });
    try {
      await auth.reloadUser();
      if (!mounted) return;
      if (auth.repository.currentUser?.emailVerified ?? false) {
        context.go('/profile');
      } else {
        setState(() => _info = l10n.verifyStillPending);
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(l10n, e));
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;
    setState(() {
      _info = null;
      _error = null;
    });
    try {
      await AuthScope.read(context).sendEmailVerification();
      if (mounted) setState(() => _info = l10n.verifyResent);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = AuthScope.of(context);
    final email = auth.user?.email ?? '';
    final info = _info;
    final error = _error;

    return AuthScaffold(
      title: l10n.verifyTitle,
      subtitle: l10n.verifyBody(email),
      header: CircleAvatar(
        radius: 36,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.mark_email_unread_outlined, size: 36, color: Theme.of(context).colorScheme.primary),
      ),
      children: [
        if (error != null) AuthErrorBanner(error),
        if (info != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Semantics(liveRegion: true, child: Text(info, textAlign: TextAlign.center)),
          ),
        FilledButton(onPressed: auth.busy ? null : _check, child: Text(l10n.verifyCheck)),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: auth.busy ? null : _resend, child: Text(l10n.verifyResend)),
        const SizedBox(height: 12),
        TextButton(onPressed: () => context.go('/profile'), child: Text(l10n.verifyLater)),
      ],
    );
  }
}
