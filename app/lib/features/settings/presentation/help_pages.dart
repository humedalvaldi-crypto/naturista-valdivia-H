import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';

/// Preguntas frecuentes. Las respuestas describen lo que la app hace hoy.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final faq = [
      (l10n.faqObservationQ, l10n.faqObservationA),
      (l10n.faqLocationQ, l10n.faqLocationA),
      (l10n.faqNotebookQ, l10n.faqNotebookA),
      (l10n.faqTrashQ, l10n.faqTrashA),
      (l10n.faqOldAppQ, l10n.faqOldAppA),
      (l10n.faqOfflineQ, l10n.faqOfflineA),
      (l10n.faqMissingQ, l10n.faqMissingA),
      (l10n.faqContactQ, l10n.faqContactA),
    ];
    return _TextPage(
      title: l10n.helpTitle,
      children: [
        for (final (i, (q, a)) in faq.indexed)
          ExpansionTile(
            key: Key('faq-$i'),
            title: Text(q),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [SelectableText(a)],
          ),
      ],
    );
  }
}

/// Privacidad y condiciones de uso, en lenguaje simple.
class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final sections = [
      (l10n.legalDataTitle, l10n.legalDataBody),
      (l10n.legalUseTitle, l10n.legalUseBody),
      (l10n.legalLocationTitle, l10n.legalLocationBody),
      (l10n.legalProvidersTitle, l10n.legalProvidersBody),
      (l10n.legalRightsTitle, l10n.legalRightsBody),
      (l10n.legalTermsTitle, l10n.legalTermsBody),
    ];
    return _TextPage(
      title: l10n.legalTitle,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(l10n.legalDraftNotice, style: theme.textTheme.bodySmall),
        ),
        for (final (title, body) in sections)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: theme.textTheme.titleMedium)),
                const SizedBox(height: 6),
                SelectableText(body),
              ],
            ),
          ),
      ],
    );
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.only(bottom: 32), children: children),
        ),
      ),
    );
  }
}
