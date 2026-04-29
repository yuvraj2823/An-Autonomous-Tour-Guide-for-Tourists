import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme.dart';
import '../../models/place_model.dart';
import '../../models/place_content_model.dart';
import '../../providers/app_text_provider.dart';
import '../../providers/content_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/ai_service.dart';
import '../../services/tts_service.dart';

class PlaceDetailScreen extends ConsumerWidget {
  final Place place;
  const PlaceDetailScreen({super.key, required this.place});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(placeContentProvider(place.id));
    final language     = ref.watch(languageProvider).language;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Hero image ──────────────────────────────────────────────
          _HeroAppBar(place: place, contentAsync: contentAsync),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Name + category
                Text(place.name,
                    style: Theme.of(context).textTheme.displayLarge),
                const SizedBox(height: 4),
                Row(children: [
                  _Chip(label: place.category, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Icon(Icons.place,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      place.vicinity,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // ── Directions row ───────────────
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.directions),
                      label: Text(ref.watch(appTextProvider(('directions', 'Directions')))),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => _launchUrl(place.directionsUrl),
                    ),
                  ),
                ]),
                const SizedBox(height: 28),

                // ── Raw Firestore content ────────────────────────────
                contentAsync.when(
                  loading: () => const _Spinner(),
                  error: (e, _) => _ErrorBox(message: e.toString()),
                  data: (content) => content == null
                      ? const _NoContent()
                      : _RawContentBody(content: content),
                ),

                // ── LLM narrative ────────────────────────────────────
                const SizedBox(height: 8),
                _LlmSection(place: place, language: language),

                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero image app bar
// ─────────────────────────────────────────────────────────────────────────────

class _HeroAppBar extends StatelessWidget {
  final Place place;
  final AsyncValue<PlaceContent?> contentAsync;
  const _HeroAppBar({required this.place, required this.contentAsync});

  @override
  Widget build(BuildContext context) {
    final imageUrl = contentAsync.valueOrNull?.imageUrl ?? '';
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: imageUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const _PlaceholderHero(),
              )
            : const _PlaceholderHero(),
      ),
    );
  }
}

class _PlaceholderHero extends StatelessWidget {
  const _PlaceholderHero();
  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A6B4A), Color(0xFF0D4F35)],
          ),
        ),
        child: const Center(
          child: Icon(Icons.place, color: Colors.white38, size: 80),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Raw Firestore content body (description, history, significance, video)
// ─────────────────────────────────────────────────────────────────────────────

class _RawContentBody extends StatelessWidget {
  final PlaceContent content;
  const _RawContentBody({required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (content.description.isNotEmpty)
          _Section(title: 'About', body: content.description),
        if (content.history.isNotEmpty)
          _Section(title: 'History', body: content.history),
        if (content.significance.isNotEmpty)
          _Section(title: 'Significance', body: content.significance),
        if (content.videoUrl.isNotEmpty) _VideoButton(url: content.videoUrl),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI LLM narrative section
// ─────────────────────────────────────────────────────────────────────────────

class _LlmSection extends ConsumerStatefulWidget {
  final Place place;
  final String language;
  const _LlmSection({required this.place, required this.language});

  @override
  ConsumerState<_LlmSection> createState() => _LlmSectionState();
}

class _LlmSectionState extends ConsumerState<_LlmSection> {
  bool _showDeepDive = false;

  @override
  Widget build(BuildContext context) {
    // Determine which provider to watch based on state
    final llmAsync = _showDeepDive 
      ? ref.watch(llmPlaceDeepDiveProvider(widget.place))
      : ref.watch(llmPlaceProvider(widget.place));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 0,
      color: AppTheme.primaryColor.withAlpha(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Allow button to stretch or align cleanly
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppTheme.primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  'AI Tour Guide',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontSize: 15),
                ),
                const SizedBox(width: 8),
                const _AiDebugBadge(),
                const Spacer(),
                // TTS play/stop button
                llmAsync.when(
                  data: (text) => text.isEmpty
                      ? const SizedBox()
                      : _TtsButton(text: text, language: widget.language),
                  loading: () => const SizedBox(),
                  error: (_, __) => const SizedBox(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            llmAsync.when(
              loading: () => Row(
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryColor),
                  ),
                  SizedBox(width: 10),
                  Text(ref.watch(appTextProvider(
                          ('generating_narrative', 'Generating narrative…'))),
                      style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
              data: (text) => text.isEmpty
                  ? const Text(
                      'Add your API key in AppConstants.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: text,
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                              .copyWith(
                            p: Theme.of(context).textTheme.bodyLarge,
                          ),
                          onTapLink: (_, href, __) async {
                            if (href != null) {
                              final uri = Uri.parse(href);
                              if (await canLaunchUrl(uri)) launchUrl(uri);
                            }
                          },
                        ),
                        if (!_showDeepDive) ...[
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primaryColor,
                                side: const BorderSide(color: AppTheme.primaryColor),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => setState(() => _showDeepDive = true),
                              child: Text(ref.watch(appTextProvider(('know_more', 'Know More')))),
                            ),
                          ),
                        ]
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// TTS control button
// ─────────────────────────────────────────────────────────────────────────────

class _TtsButton extends StatefulWidget {
  final String text;
  final String language;
  const _TtsButton({required this.text, required this.language});

  @override
  State<_TtsButton> createState() => _TtsButtonState();
}

class _TtsButtonState extends State<_TtsButton> {
  bool _playing = false;

  Future<void> _toggle() async {
    if (_playing) {
      await TtsService.stop();
      if (mounted) setState(() => _playing = false);
    } else {
      setState(() => _playing = true);
      await TtsService.speak(widget.text, language: widget.language);
      if (mounted) setState(() => _playing = false);
    }
  }

  @override
  void dispose() {
    TtsService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(
          _playing ? Icons.stop_circle : Icons.play_circle_outline,
          color: AppTheme.primaryColor,
        ),
        tooltip: _playing ? 'Stop narration' : 'Listen',
        onPressed: _toggle,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final String body;
  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(body, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 20),
        ],
      );
}

class _VideoButton extends StatelessWidget {
  final String url;
  const _VideoButton({required this.url});

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        icon: const Icon(Icons.play_circle_outline,
            color: AppTheme.primaryColor),
        label: const Text('Watch Video'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryColor,
          side: const BorderSide(color: AppTheme.primaryColor),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) await launchUrl(uri);
        },
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
}

class _NoContent extends StatelessWidget {
  const _NoContent();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          children: [
            const Icon(Icons.info_outline,
                color: AppTheme.textSecondary, size: 40),
            const SizedBox(height: 8),
            Text(
              'No Firestore document found for this place.\nCheck terminal for the exact placeId.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  const _ErrorBox({required this.message});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(26),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _AiDebugBadge extends StatelessWidget {
  const _AiDebugBadge();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AiDebugState>(
      valueListenable: AiService.debugState,
      builder: (_, s, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withAlpha(24),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '${s.language} · ${s.translationSource} · ${s.narrativeSource}',
          style: const TextStyle(
            fontSize: 10,
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
