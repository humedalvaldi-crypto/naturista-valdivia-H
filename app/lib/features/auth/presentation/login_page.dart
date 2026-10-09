import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../shared/branding/brand.dart';
import '../application/auth_controller.dart';
import '../domain/auth_user.dart';
import 'auth_widgets.dart';

/// Pantalla 21 de la lámina: Iniciar sesión (correo/contraseña y Google).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.from});

  /// Ruta a la que volver después de entrar.
  final String? from;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _attempt(Future<void> Function() action) async {
    final l10n = context.l10n;
    setState(() => _error = null);
    try {
      await action();
      // El router redirige automáticamente al cambiar la sesión.
    } on AuthException catch (e) {
      if (!mounted || e.code == AuthErrorCode.cancelled) return;
      setState(() => _error = authErrorText(l10n, e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = authErrorText(l10n, e));
    }
  }

  void _submitEmail() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = AuthScope.read(context);
    _attempt(() => auth.signInWithEmail(_email.text, _password.text));
  }

  String _withFrom(String path) {
    final from = widget.from;
    return from == null ? path : Uri(path: path, queryParameters: {'from': from}).toString();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = AuthScope.of(context);
    final busy = auth.busy;
    final error = _error;

    return AuthScaffold(
      title: l10n.loginTitle,
      subtitle: l10n.loginSubtitle,
      header: BrandMark(size: 72, color: Theme.of(context).colorScheme.primary),
      children: [
        if (error != null) AuthErrorBanner(error),
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('login-email'),
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
                  key: const Key('login-password'),
                  controller: _password,
                  label: l10n.passwordLabel,
                  validator: (v) => AuthValidators.required(l10n, v),
                  onSubmitted: (_) => _submitEmail(),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : () => context.push('/forgot-password'),
            child: Text(l10n.forgotPassword),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('login-submit'),
          onPressed: busy ? null : _submitEmail,
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l10n.loginTitle),
        ),
        const OrDivider(),
        GoogleButton(onPressed: busy ? null : () => _attempt(AuthScope.read(context).signInWithGoogle)),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l10n.noAccount),
            TextButton(
              key: const Key('go-register'),
              onPressed: busy ? null : () => context.go(_withFrom('/register')),
              child: Text(l10n.createAccount),
            ),
          ],
        ),
      ],
    );
  }
}
