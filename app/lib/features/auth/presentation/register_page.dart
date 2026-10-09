import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../application/auth_controller.dart';
import '../domain/auth_user.dart';
import 'auth_widgets.dart';

/// Pantalla 22 de la lámina: Registro con correo y contraseña.
/// Tras crear la cuenta, Firebase envía el correo de verificación.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key, this.from});

  final String? from;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    try {
      await AuthScope.read(context).register(name: _name.text, email: _email.text, password: _password.text);
    } catch (e) {
      if (!mounted) return;
      if (e is AuthException && e.code == AuthErrorCode.cancelled) return;
      setState(() => _error = authErrorText(l10n, e));
    }
  }

  Future<void> _google() async {
    final l10n = context.l10n;
    setState(() => _error = null);
    try {
      await AuthScope.read(context).signInWithGoogle();
    } catch (e) {
      if (!mounted) return;
      if (e is AuthException && e.code == AuthErrorCode.cancelled) return;
      setState(() => _error = authErrorText(l10n, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = AuthScope.of(context).busy;
    final error = _error;
    final from = widget.from;

    return AuthScaffold(
      title: l10n.createAccount,
      subtitle: l10n.registerSubtitle,
      children: [
        if (error != null) AuthErrorBanner(error),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('register-name'),
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l10n.nameLabel),
                  validator: (v) => AuthValidators.required(l10n, v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const Key('register-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: l10n.emailLabel),
                  validator: (v) => AuthValidators.email(l10n, v),
                ),
                const SizedBox(height: 14),
                PasswordField(
                  key: const Key('register-password'),
                  controller: _password,
                  label: l10n.passwordLabel,
                  helperText: l10n.passwordHint,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => AuthValidators.newPassword(l10n, v),
                ),
                const SizedBox(height: 14),
                PasswordField(
                  key: const Key('register-confirm'),
                  controller: _confirm,
                  label: l10n.confirmPasswordLabel,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (v) => v != _password.text ? l10n.errorPasswordMismatch : null,
                  onSubmitted: (_) => _submit(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('register-submit'),
          onPressed: busy ? null : _submit,
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.createAccount),
        ),
        const OrDivider(),
        GoogleButton(onPressed: busy ? null : _google),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.haveAccount),
            TextButton(
              onPressed: busy
                  ? null
                  : () => context.go(from == null ? '/login' : Uri(path: '/login', queryParameters: {'from': from}).toString()),
              child: Text(l10n.loginTitle),
            ),
          ],
        ),
      ],
    );
  }
}
