import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../domain/auth_user.dart';

/// Texto para cada error de autenticación.
String authErrorText(AppLocalizations l10n, Object error) {
  if (error is! AuthException) return l10n.authErrUnknown;
  return switch (error.code) {
    AuthErrorCode.invalidCredentials => l10n.authErrInvalidCredentials,
    AuthErrorCode.emailInUse => l10n.authErrEmailInUse,
    AuthErrorCode.weakPassword => l10n.authErrWeakPassword,
    AuthErrorCode.invalidEmail => l10n.authErrInvalidEmail,
    AuthErrorCode.userDisabled => l10n.authErrUserDisabled,
    AuthErrorCode.tooManyRequests => l10n.authErrTooMany,
    AuthErrorCode.network => l10n.authErrNetwork,
    AuthErrorCode.accountExistsWithDifferentCredential => l10n.authErrDifferentCredential,
    AuthErrorCode.multiFactorRequired => l10n.authErrMfa,
    AuthErrorCode.requiresRecentLogin => l10n.authErrRecentLogin,
    AuthErrorCode.notConfigured => l10n.authErrNotConfigured,
    AuthErrorCode.cancelled || AuthErrorCode.unknown => l10n.authErrUnknown,
  };
}

/// Validaciones de formulario compartidas.
abstract final class AuthValidators {
  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static const minPasswordLength = 8;

  static String? required(AppLocalizations l10n, String? v) =>
      (v == null || v.trim().isEmpty) ? l10n.errorRequired : null;

  static String? email(AppLocalizations l10n, String? v) {
    if (v == null || v.trim().isEmpty) return l10n.errorRequired;
    return _email.hasMatch(v.trim()) ? null : l10n.errorEmail;
  }

  static String? newPassword(AppLocalizations l10n, String? v) {
    if (v == null || v.isEmpty) return l10n.errorRequired;
    return v.length < minPasswordLength ? l10n.errorPasswordShort : null;
  }
}

/// Estructura común de las pantallas de cuenta (lámina, sección 2):
/// columna centrada, título grande, campos y botón principal ancho.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.header,
    required this.children,
    this.showBack = true,
  });

  final String title;
  final String? subtitle;
  final Widget? header;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final header = this.header;
    final subtitle = this.subtitle;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: showBack),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (header != null) ...[Center(child: header), const SizedBox(height: 20)],
                  Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 28),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mensaje de error en línea, anunciado a lectores de pantalla.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))),
          ],
        ),
      ),
    );
  }
}

class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.helperText,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final String? helperText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String> autofillHints;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onSubmitted,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        suffixIcon: IconButton(
          tooltip: _obscure ? l10n.showPassword : l10n.hidePassword,
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

/// Separador "o" entre el acceso con correo y con Google.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Expanded(child: Divider(color: color)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(context.l10n.orDivider),
          ),
          Expanded(child: Divider(color: color)),
        ],
      ),
    );
  }
}

class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      key: const Key('google-sign-in'),
      onPressed: onPressed,
      icon: const Text('G', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      label: Text(context.l10n.continueWithGoogle),
    );
  }
}
