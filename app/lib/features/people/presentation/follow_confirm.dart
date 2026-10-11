import 'package:flutter/material.dart';

import '../../../core/l10n/l10n.dart';

/// Pide confirmación antes de dejar de seguir a alguien.
Future<bool> confirmUnfollow(BuildContext context, String name) async {
  final l10n = context.l10n;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.unfollowConfirm(name)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
        FilledButton(key: const Key('unfollow-confirm'), onPressed: () => Navigator.pop(context, true), child: Text(l10n.unfollow)),
      ],
    ),
  );
  return ok == true;
}
