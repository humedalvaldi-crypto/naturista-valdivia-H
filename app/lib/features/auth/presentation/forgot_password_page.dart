import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../application/auth_controller.dart';
import '../domain/auth_user.dart';
import 'auth_widgets.dart';

/// Pantalla 28 de la lámina: Recuperar contraseña.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  String? _error;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final email = _email.text.trim();
    try {
      await AuthScope.read(context).sendPasswordReset(email);
      if (mounted) setState(() => _sentTo = email);
    } on AuthException catch (e) {
      if (!mounted) return;
      // Por privacidad no revelamos si el correo existe.
      if (e.code == AuthErrorCode.invalidCredentials) {
        setState(() => _sentTo = email);
      } else {
        setState(() => _error = authErrorText(l10n, e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = AuthScope.of(context).busy;
    final error = _error;
    final sentTo = _sentTo;

    return AuthScaffold(
      title: l10n.forgotTitle,
      subtitle: sentTo == null ? l10n.forgotBody : null,
      header: CircleAvatar(
        radius: 32,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.lock_reset, size: 32, color: Theme.of(context).colorScheme.primary),
      ),
      children: [
        if (sentTo != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(l10n.forgotSent(sentTo), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: () => context.go('/login'), child: Text(l10n.backToLogin)),
        ] else ...[
          if (error != null) AuthErrorBanner(error),
          Form(
            key: _formKey,
            child: TextFormField(
              key: const Key('forgot-email'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              decoration: InputDecoration(labelText: l10n.emailLabel),
              validator: (v) => AuthValidators.email(l10n, v),
              onFieldSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('forgot-submit'),
            onPressed: busy ? null : _submit,
            child: Text(l10n.forgotButton),
          ),
        ],
      ],
    );
  }
}
