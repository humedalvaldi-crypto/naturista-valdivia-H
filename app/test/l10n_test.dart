import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Comprueba que español e inglés tienen exactamente las mismas claves y
/// los mismos marcadores de posición.
void main() {
  Map<String, dynamic> load(String lang) =>
      jsonDecode(File('l10n/app_$lang.arb').readAsStringSync()) as Map<String, dynamic>;

  Iterable<String> messageKeys(Map<String, dynamic> arb) => arb.keys.where((k) => !k.startsWith('@'));

  test('es y en tienen las mismas claves', () {
    final es = load('es');
    final en = load('en');
    expect(messageKeys(en).toSet(), messageKeys(es).toSet());
  });

  test('los marcadores declarados aparecen en ambos idiomas', () {
    final es = load('es');
    final en = load('en');
    for (final key in messageKeys(es)) {
      final meta = es['@$key'];
      final declared = meta is Map<String, dynamic> && meta['placeholders'] is Map<String, dynamic>
          ? (meta['placeholders'] as Map<String, dynamic>).keys
          : const <String>[];
      for (final name in declared) {
        // `{name}` simple o `{name, plural, ...}`.
        final pattern = RegExp('\\{$name[,}]');
        expect(pattern.hasMatch(es[key] as String), isTrue, reason: 'es.$key usa {$name}');
        expect(pattern.hasMatch(en[key] as String), isTrue, reason: 'en.$key usa {$name}');
      }
    }
  });

  test('ningún mensaje en inglés está vacío', () {
    final en = load('en');
    for (final key in messageKeys(en)) {
      expect((en[key] as String).trim(), isNotEmpty, reason: key);
    }
  });
}
