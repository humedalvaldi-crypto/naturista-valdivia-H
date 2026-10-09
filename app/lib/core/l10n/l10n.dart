import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';

export 'generated/app_localizations.dart';

extension L10nContext on BuildContext {
  /// Atajo: `context.l10n.navHome`.
  AppLocalizations get l10n => AppLocalizations.of(this);
}
