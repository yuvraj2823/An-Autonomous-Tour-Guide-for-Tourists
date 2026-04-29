import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'language_provider.dart';

final appTextProvider =
    Provider.family<String, (String, String)>((ref, args) {
  final (key, fallback) = args;
  final langState = ref.watch(languageProvider);
  
  if (langState.language == 'English') {
    return fallback;
  }
  
  // Lookup the translated string using the English fallback as the key
  return langState.translations[fallback] ?? fallback;
});

