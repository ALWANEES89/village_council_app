import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localePreferenceKey = 'app_locale';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>(
  (ref) => LocaleNotifier(),
);

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier({Future<SharedPreferences>? preferences})
      : _preferences = preferences ?? SharedPreferences.getInstance(),
        super(const Locale('ar')) {
    ready = _restore();
  }

  final Future<SharedPreferences> _preferences;
  late final Future<void> ready;

  Future<void> _restore() async {
    final preferences = await _preferences;
    final languageCode = preferences.getString(_localePreferenceKey);
    if (languageCode == 'ar' || languageCode == 'en') {
      state = Locale(languageCode!);
    }
  }

  Future<void> setLocale(Locale locale) async {
    if (!const {'ar', 'en'}.contains(locale.languageCode)) return;
    state = Locale(locale.languageCode);
    final preferences = await _preferences;
    await preferences.setString(_localePreferenceKey, locale.languageCode);
  }
}
