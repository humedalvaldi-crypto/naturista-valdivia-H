import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Comprueba que español e inglés tienen exactamente las mismas claves y
/// los mismos marcadores de posición.
void main() {
  Map<String, dynamic> load(String lang) =>
      jsonDecode(File('l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

  Iterable<String> messageKeys(Map<String, dynamic> arb) => arb.keys.where((k) => !k.startsWith('@'));

  Set<String> placeholders(String text) =>
      RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

  test('es y en tienen las mismas claves', () {
    final es = load('es');
    final en = load('en');
    expect(messageKeys(en).toSet(), messageKeys(es).toSet());
  });

  test('los marcadores coinciden en cada mensaje', () {
    final es = load('es');
    final en = load('en');
    for (final key in messageKeys(es)) {
      expect(placeholders(en[key] as String), placeholders(es[key] as String), reason: key);
    }
  });

  test('ningún mensaje en inglés está vacío', () {
    final en = load('en');
    for (final key in messageKeys(en)) {
      expect((en[key] as String).trim(), isNotEmpty, reason: key);
    }
  });
}
