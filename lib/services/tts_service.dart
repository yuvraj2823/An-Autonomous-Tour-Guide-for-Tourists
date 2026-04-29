import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech service wrapper — Phase 9.
///
/// flutter_tts reads text aloud using the phone's on-device TTS engine.
/// Think of it as the "voice" of the tour guide.
class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static bool _initialised = false;
  static bool _isSpeaking  = false;

  // ── Language codes for supported languages ──────────────────────────────
  static const Map<String, String> languageTtsCode = {
    'English':    'en-US',
    'Hindi':      'hi-IN',
    'Arabic':     'ar-SA',
    'Tamil':      'ta-IN',
    'French':     'fr-FR',
    'Spanish':    'es-ES',
    'German':     'de-DE',
    'Japanese':   'ja-JP',
  };

  static Future<void> _init() async {
    if (_initialised) return;
    await _tts.setSpeechRate(0.5);   // slightly slower for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _tts.setCompletionHandler(() => _isSpeaking = false);
    _tts.setCancelHandler(()    => _isSpeaking = false);
    _tts.setErrorHandler((_)    => _isSpeaking = false);
    _initialised = true;
  }

  /// Speak [text] aloud in [language] (English name, e.g. "Hindi").
  static Future<void> speak(String text, {String language = 'English'}) async {
    await _init();
    final code = languageTtsCode[language] ?? 'en-US';
    final supported = await _tts.isLanguageAvailable(code);
    await _tts.setLanguage(supported == true ? code : 'en-US');
    await _tts.stop(); // stop any current speech first
    _isSpeaking = true;

    // Strip markdown formatting before reading
    final plain = _stripMarkdown(text);
    await _tts.speak(plain);
  }

  static Future<void> stop() async {
    await _tts.stop();
    _isSpeaking = false;
  }

  static bool get isSpeaking => _isSpeaking;

  /// Remove basic markdown symbols so TTS doesn't read "asterisk asterisk".
  static String _stripMarkdown(String mdText) {
    return mdText
        .replaceAll(RegExp(r'\*{1,3}'), '')  // bold/italic markers
        .replaceAll(RegExp(r'#{1,6} '),  '')  // heading markers
        .replaceAll(RegExp(r'_'),         '')  // underscores
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1') // links→text
        .replaceAll(RegExp(r'\n{2,}'), '\n'); // collapse blank lines
  }
}
