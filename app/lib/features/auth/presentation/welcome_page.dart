import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';
import '../../settings/application/settings_controller.dart';

/// Pantallas 3–5 de la lámina (Bienvenida y Onboarding), con las
/// ilustraciones propias del proyecto. Se muestran una sola vez.
class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _controller = PageController();
  int _index = 0;

  static const _images = [
    'assets/illustrations/aves/chucao.jpg',
    'assets/illustrations/flora/copihue2.jpg',
    'assets/illustrations/aves/cisnes.jpg',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    // El router reacciona al cambio y continúa hacia el inicio.
    SettingsScope.read(context).completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final pages = [
      (l10n.onb1Title, l10n.onb1Body),
      (l10n.onb2Title, l10n.onb2Body),
      (l10n.onb3Title, l10n.onb3Body),
    ];
    final isLast = _index == pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(key: const Key('onboarding-skip'), onPressed: _finish, child: Text(l10n.skip)),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: pages.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      final (title, body) = pages[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: Image.asset(
                                  _images[i],
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, _, _) => const SizedBox.shrink(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(title, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                            const SizedBox(height: 10),
                            Text(
                              body,
                              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: i == _index ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: i == _index ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                    key: const Key('onboarding-next'),
                    onPressed: isLast
                        ? _finish
                        : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOut,
                            ),
                      child: Text(isLast ? l10n.getStarted : l10n.next),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
