import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app/constants.dart';

class AiDebugState {
  final String language;
  final String translationSource;
  final String narrativeSource;
  final DateTime updatedAt;

  const AiDebugState({
    required this.language,
    required this.translationSource,
    required this.narrativeSource,
    required this.updatedAt,
  });

  AiDebugState copyWith({
    String? language,
    String? translationSource,
    String? narrativeSource,
  }) {
    return AiDebugState(
      language: language ?? this.language,
      translationSource: translationSource ?? this.translationSource,
      narrativeSource: narrativeSource ?? this.narrativeSource,
      updatedAt: DateTime.now(),
    );
  }
}

class AiService {
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _wikipediaSearchUrl = 'https://en.wikipedia.org/w/api.php';
  static const String _wikipediaSummaryUrl = 'https://en.wikipedia.org/api/rest_v1/page/summary';
  static Future<void> _requestQueue = Future.value();
  static final Map<String, String> _cache = {};
  static final ValueNotifier<AiDebugState> debugState =
      ValueNotifier<AiDebugState>(
    AiDebugState(
      language: 'English',
      translationSource: 'idle',
      narrativeSource: 'idle',
      updatedAt: DateTime.now(),
    ),
  );

  static String _cacheKey(String key, String input) => '$key||$input'.hashCode.toString();

  static bool looksLikeFailure(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return t.startsWith('_Groq') || t.startsWith('_Gemini') || t.contains('API error');
  }

  static void clearCache() => _cache.clear();
  static void reportTranslationSource(String language, String source) {
    debugState.value = debugState.value.copyWith(
      language: language,
      translationSource: source,
    );
  }

  static String _langInstruction(String language) {
    const mapping = <String, String>{
      'English': 'English',
      'Hindi': 'Hindi (Devanagari script)',
      'Marathi': 'Marathi (Devanagari script)',
      'Arabic': 'Arabic (Modern Standard Arabic script)',
      'Tamil': 'Tamil (Tamil script)',
      'French': 'French',
      'Spanish': 'Spanish',
      'German': 'German',
      'Japanese': 'Japanese (natural Japanese script)',
    };
    return mapping[language] ?? language;
  }

  static Future<String> _fetchWikipediaContext(String query) async {
    try {
      final searchUri = Uri.parse(
        '$_wikipediaSearchUrl?action=query&list=search&format=json&srsearch=${Uri.encodeQueryComponent(query)}&srlimit=2&utf8=1',
      );
      final searchResp = await http.get(searchUri).timeout(const Duration(seconds: 8));
      if (searchResp.statusCode != 200) return '';
      final searchData = jsonDecode(searchResp.body) as Map<String, dynamic>;
      final results = (searchData['query']?['search'] as List?) ?? const [];
      if (results.isEmpty) return '';

      final snippets = <String>[];
      for (final r in results.take(2)) {
        final title = (r['title'] ?? '').toString().trim();
        if (title.isEmpty) continue;
        final summaryUri = Uri.parse(
          '$_wikipediaSummaryUrl/${Uri.encodeComponent(title)}',
        );
        final summaryResp =
            await http.get(summaryUri).timeout(const Duration(seconds: 8));
        if (summaryResp.statusCode != 200) continue;
        final summaryData = jsonDecode(summaryResp.body) as Map<String, dynamic>;
        final extract = (summaryData['extract'] ?? '').toString().trim();
        final pageTitle = (summaryData['title'] ?? title).toString().trim();
        if (extract.isNotEmpty) {
          snippets.add('SOURCE: Wikipedia | TITLE: $pageTitle | EXTRACT: $extract');
        }
      }
      return snippets.join('\n\n');
    } catch (_) {
      return '';
    }
  }

  static Future<String> generatePlaceNarrative(
    String name,
    String description,
    String history,
    String significance, {
    String language = 'English',
    bool isDeepDive = false,
  }) async {
    final baseInfo = [
      'PLACE: $name',
      if (description.trim().isNotEmpty) 'DESCRIPTION: $description',
      if (history.trim().isNotEmpty) 'HISTORY: $history',
      if (significance.trim().isNotEmpty) 'SIGNIFICANCE: $significance',
    ].join('\n');
    final webContext = await _fetchWikipediaContext(name);
    final languageDirective = _langInstruction(language);
    final prompt = isDeepDive
        ? '''
You are a factual tour guide.
Output language: $languageDirective.

Use these sources only:
1) FIREBASE DATA (primary)
2) WEB DATA snippets below (secondary, if present)

Rules:
- Do NOT invent facts.
- If details conflict or are missing, explicitly say you are not sure.
- If there is very little reliable information, say: "There is not much reliable information available about this place."
- 100-180 words, max 2 short paragraphs.

FIREBASE DATA:
$baseInfo

WEB DATA:
${webContext.isEmpty ? 'No reliable web snippets found.' : webContext}
'''
        : '''
You are a factual tour guide.
Output language: $languageDirective.

Use FIREBASE DATA first; use WEB DATA only if relevant.
Do NOT hallucinate. If not sure, say so.
If information is minimal, say: "There is not much reliable information available about this place."
Write 20-70 words.

FIREBASE DATA:
$baseInfo

WEB DATA:
${webContext.isEmpty ? 'No reliable web snippets found.' : webContext}
''';
    final key = _cacheKey('place_${isDeepDive ? 'full' : 'base'}_$language', baseInfo);
    final cached = _cache[key];
    if (cached != null && !looksLikeFailure(cached)) return cached;
    final out = await _generateContent(
      prompt,
      model: isDeepDive ? AppConstants.groqModelFull : AppConstants.groqModelFast,
      maxTokens: isDeepDive ? 500 : 200,
    );
    if (looksLikeFailure(out)) {
      return 'The guide is busy right now. Please try again in a few seconds.';
    }
    _cache[key] = out;
    debugState.value = debugState.value.copyWith(
      language: language,
      narrativeSource: webContext.isEmpty ? 'firebase-only' : 'firebase+web',
    );
    return out;
  }

  static Future<String> generateBeaconNarrative(
    String objectName,
    String description,
    String history, {
    String language = 'English',
    bool isDeepDive = false,
  }) async {
    final baseInfo = [
      'EXHIBIT: $objectName',
      if (description.trim().isNotEmpty) 'DESCRIPTION: $description',
      if (history.trim().isNotEmpty) 'HISTORY: $history',
    ].join('\n');
    final webContext = await _fetchWikipediaContext(objectName);
    final languageDirective = _langInstruction(language);
    final prompt = isDeepDive
        ? '''
You are a factual museum guide.
Output language: $languageDirective.

Use these sources only:
1) FIREBASE DATA (primary)
2) WEB DATA snippets (secondary)

Rules:
- Never invent facts.
- If unsure, clearly state uncertainty.
- If information is scarce, say: "There is not much reliable information available about this exhibit."
- 90-150 words, max 2 short paragraphs.

FIREBASE DATA:
$baseInfo

WEB DATA:
${webContext.isEmpty ? 'No reliable web snippets found.' : webContext}
'''
        : '''
You are a factual museum guide.
Output language: $languageDirective.
Use FIREBASE DATA first and WEB DATA only if relevant.
No hallucinations. If unsure, say so.
Write 10-30 words.

FIREBASE DATA:
$baseInfo

WEB DATA:
${webContext.isEmpty ? 'No reliable web snippets found.' : webContext}
''';
    final key = _cacheKey('beacon_${isDeepDive ? 'full' : 'base'}_$language', baseInfo);
    final cached = _cache[key];
    if (cached != null && !looksLikeFailure(cached)) return cached;
    final out = await _generateContent(
      prompt,
      model: isDeepDive ? AppConstants.groqModelFull : AppConstants.groqModelFast,
      maxTokens: isDeepDive ? 400 : 120,
    );
    if (looksLikeFailure(out)) {
      return 'The guide is busy right now. Please try again in a few seconds.';
    }
    _cache[key] = out;
    debugState.value = debugState.value.copyWith(
      language: language,
      narrativeSource: webContext.isEmpty ? 'firebase-only' : 'firebase+web',
    );
    return out;
  }

  static Future<Map<String, String>> translateBatch(
      List<String> texts, String targetLanguage) async {
    final toTranslate = texts.where((t) => t.trim().isNotEmpty).toSet().toList();
    if (toTranslate.isEmpty || targetLanguage == 'English') {
      return {for (final t in texts) t: t};
    }
    final results = <String, String>{};
    final missing = <String>[];
    for (final t in toTranslate) {
      final c = _cache[_cacheKey('translate_$targetLanguage', t)];
      if (c != null && !looksLikeFailure(c)) {
        results[t] = c;
      } else {
        missing.add(t);
      }
    }
    if (missing.isEmpty) return results;

    final languageDirective = _langInstruction(targetLanguage);
    final prompt = '''
Translate the provided English strings into $languageDirective.
Output ONLY valid JSON object with original English string as key and translated text as value.
No markdown, no explanation, no extra keys.
If a phrase cannot be translated confidently, still provide best natural translation.
STRINGS: ${jsonEncode(missing)}
''';
    final raw = await _generateContent(
      prompt,
      model: AppConstants.groqModelFast,
      maxTokens: 1400,
    );
    if (looksLikeFailure(raw)) return results;
    try {
      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final decoded = jsonDecode(clean) as Map<String, dynamic>;
      for (final e in decoded.entries) {
        final value = e.value.toString();
        if (looksLikeFailure(value)) continue;
        results[e.key] = value;
        _cache[_cacheKey('translate_$targetLanguage', e.key)] = value;
      }
    } catch (_) {
      // Fallback to per-item translation if batch JSON is malformed.
      for (final item in missing) {
        final t = await translateText(item, targetLanguage);
        if (t != null && t.isNotEmpty && !looksLikeFailure(t)) {
          results[item] = t;
        }
      }
    }
    return results;
  }

  static Future<String?> translateText(String text, String targetLanguage) async {
    if (text.trim().isEmpty || targetLanguage == 'English') return text;
    final key = _cacheKey('translate_$targetLanguage', text);
    final c = _cache[key];
    if (c != null && !looksLikeFailure(c)) return c;
    final languageDirective = _langInstruction(targetLanguage);
    for (var i = 0; i < AppConstants.llmMaxHttpRetries; i++) {
      final raw = await _generateContent(
        '''
Translate this English text into $languageDirective.
Return only translated text in the target language script.
No transliteration unless standard for that language.
TEXT: $text
''',
        model: AppConstants.groqModelFast,
        maxTokens: 150,
      );
      if (looksLikeFailure(raw)) {
        await Future.delayed(Duration(seconds: 2 + i));
        continue;
      }
      final cleaned = raw
          .replaceAll(
              RegExp(r'^["\u2018\u2019\u201C\u201D]|["\u2018\u2019\u201C\u201D]$'),
              '')
          .trim();
      _cache[key] = cleaned;
      return cleaned;
    }
    return null;
  }

  static Future<String> _generateContent(
    String prompt, {
    required String model,
    required int maxTokens,
  }) async {
    if (AppConstants.groqApiKey.isEmpty) {
      return '_Groq API key not configured._';
    }
    final uri = Uri.parse(_groqUrl);
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
      'temperature': 0.2,
      'max_tokens': maxTokens,
    });
    final completer = Completer<String>();
    _requestQueue = _requestQueue.then((_) async {
      var retries = 0;
      while (retries <= AppConstants.llmMaxHttpRetries) {
        try {
          final response = await http.post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${AppConstants.groqApiKey}',
            },
            body: body,
          ).timeout(const Duration(seconds: 25));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final choices = data['choices'] as List?;
            if (choices == null || choices.isEmpty) {
              completer.complete('_Groq empty response._');
            } else {
              final msg = choices.first['message'] as Map<String, dynamic>?;
              completer.complete((msg?['content'] as String? ?? '').trim());
            }
            break;
          }
          if (response.statusCode == 429 ||
              response.statusCode == 502 ||
              response.statusCode == 503) {
            retries++;
            if (retries > AppConstants.llmMaxHttpRetries) {
              completer.complete('_Groq API rate limit exceeded._');
              break;
            }
            await Future.delayed(Duration(seconds: 2 * (1 << retries.clamp(0, 4))));
            continue;
          }
          completer.complete('_Groq API error ${response.statusCode}._');
          break;
        } on TimeoutException {
          completer.complete('_Groq request timed out._');
          break;
        } catch (e) {
          completer.complete('_Groq error: $e');
          break;
        }
      }
      await Future.delayed(AppConstants.llmMinIntervalBetweenRequests);
    });
    return completer.future;
  }
}
