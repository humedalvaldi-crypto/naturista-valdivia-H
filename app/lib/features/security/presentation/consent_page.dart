import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../application/consent_controller.dart';

/// Aceptar los términos y confirmar la edad mínima. Ninguna casilla viene
/// marcada y el botón solo se activa con ambas.
class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _terms = false;
  bool _age = false;
  bool _sending = false;

  Future<void> _accept() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final consent = ConsentScope.of(context);
    setState(() => _sending = true);
    try {
      await consent.accept();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e is ApiException ? e.message : l10n.errorGeneric)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final consent = ConsentScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.consentTitle), automaticallyImplyLeading: false),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(l10n.consentIntro),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(l10n.consentSummary),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('consent-read-terms'),
                  onPressed: () => context.push('/settings/legal'),
                  icon: const Icon(Icons.policy_outlined),
                  label: Text(l10n.consentReadTerms),
                ),
              ),
              CheckboxListTile(
                key: const Key('consent-terms'),
                value: _terms,
                onChanged: (v) => setState(() => _terms = v ?? false),
                title: Text(l10n.consentTermsCheck),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              CheckboxListTile(
                key: const Key('consent-age'),
                value: _age,
                onChanged: (v) => setState(() => _age = v ?? false),
                title: Text(l10n.consentAgeCheck(consent.minAge)),
                subtitle: Text(l10n.consentAgeHint),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('consent-accept'),
                onPressed: _terms && _age && !_sending ? _accept : null,
                child: Text(l10n.consentAccept),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('consent-sign-out'),
                onPressed: () => AuthScope.read(context).signOut(),
                child: Text(l10n.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
