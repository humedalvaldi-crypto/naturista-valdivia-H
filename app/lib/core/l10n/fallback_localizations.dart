import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Idiomas de la app que Flutter no trae para sus propios textos (botones de
/// sistema, fechas, selector de hora): se usan los de [fallback].
const _fallbackFor = {'arn': Locale('es')};

Locale _resolve(Locale locale) => _fallbackFor[locale.languageCode] ?? locale;

class FallbackMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const FallbackMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _fallbackFor.containsKey(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) => GlobalMaterialLocalizations.delegate.load(_resolve(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<MaterialLocalizations> old) => false;
}

class FallbackCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const FallbackCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _fallbackFor.containsKey(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) => GlobalCupertinoLocalizations.delegate.load(_resolve(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<CupertinoLocalizations> old) => false;
}

class FallbackWidgetsLocalizationsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const FallbackWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => _fallbackFor.containsKey(locale.languageCode);

  @override
  Future<WidgetsLocalizations> load(Locale locale) => GlobalWidgetsLocalizations.delegate.load(_resolve(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<WidgetsLocalizations> old) => false;
}
