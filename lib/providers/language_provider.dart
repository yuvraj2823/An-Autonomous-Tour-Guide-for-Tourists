import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai_service.dart';

/// Available display languages (also controls Gemini prompt language + TTS).
const List<String> supportedLanguages = [
  'English',
  'Hindi',
  'Arabic',
  'Tamil',
  'French',
  'Spanish',
  'German',
  'Japanese',
];

const String _langPrefKey = 'selected_language';
const String _transPrefKey = 'cached_translations';

class LanguageState {
  final String language;
  final Map<String, String> translations;

  const LanguageState({
    required this.language,
    required this.translations,
  });

  LanguageState copyWith({
    String? language,
    Map<String, String>? translations,
  }) {
    return LanguageState(
      language: language ?? this.language,
      translations: translations ?? this.translations,
    );
  }
}

/// Base English strings used for app-wide UI translation.
const Map<String, String> baseEnglishStrings = {
  'home': 'Home',
  'outdoor': 'Outdoor',
  'indoor': 'Indoor',
  'outdoor_explorer': 'Outdoor Explorer',
  'directions': 'Directions',
  'select_language': 'Select Language',
  'loading_places': 'Loading places…',
  'acquiring_gps': 'Acquiring GPS location…',
  'switching_mode': 'Switching mode…',
  'outdoor_mode_active': 'Outdoor Mode — GPS Active',
  'indoor_mode_active': 'Indoor Mode — BLE Active',
  'generating_narrative': 'Generating narrative…',
  'know_more': 'Know More',
  'refresh': 'Refresh',
  'ai_guide': 'AI Guide',
  'approaching_venue': 'Approaching venue…',
};

/// Selected language and its cached translations.
final languageProvider =
    StateNotifierProvider<LanguageNotifier, LanguageState>(
  (ref) => LanguageNotifier(),
);

class LanguageNotifier extends StateNotifier<LanguageState> {
  LanguageNotifier() : super(const LanguageState(language: 'English', translations: {})) {
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLang = prefs.getString(_langPrefKey);
    final savedTrans = prefs.getString(_transPrefKey);

    String lang = 'English';
    Map<String, String> trans = {};

    if (savedLang != null && supportedLanguages.contains(savedLang)) {
      lang = savedLang;
    }
    if (savedTrans != null) {
      try {
        trans = Map<String, String>.from(jsonDecode(savedTrans));
      } catch (_) {}
    }

    state = LanguageState(language: lang, translations: trans);
    
    // Ensure translations are up-to-date
    _updateTranslations(lang);
  }

  Future<void> setLanguage(String lang) async {
    if (!supportedLanguages.contains(lang)) return;
    
    state = state.copyWith(language: lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langPrefKey, lang);

    await _updateTranslations(lang);
  }

  Future<void> _updateTranslations(String lang) async {
    if (lang == 'English') {
      state = state.copyWith(translations: {});
      return;
    }

    // Determine missing translations based on the base English string values
    final missing = baseEnglishStrings.values
        .where((val) => !state.translations.containsKey(val))
        .toList();

    if (missing.isEmpty) return;

    final newTranslations = await AiService.translateBatch(missing, lang);
    if (newTranslations.isNotEmpty) {
      final updatedMap = Map<String, String>.from(state.translations)..addAll(newTranslations);
      state = state.copyWith(translations: updatedMap);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_transPrefKey, jsonEncode(updatedMap));
    }
  }
}
