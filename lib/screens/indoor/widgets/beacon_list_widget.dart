import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';
import '../../../app/venue_config.dart';
import '../../../models/ble_beacon_model.dart';
import '../../../models/beacon_model.dart';
import '../../../providers/content_provider.dart';
import '../../../providers/language_provider.dart';
import '../../../services/tts_service.dart';

/// Shows a scrollable, card-based list of currently detected BLE beacons.
/// Each card shows: exhibit name, signal strength, distance, and (when
/// expanded) Firestore content + Gemini narrative.
class BeaconListWidget extends ConsumerWidget {
  final List<BleBeacon> beacons;
  final ScrollController? scrollController;
  const BeaconListWidget({super.key, required this.beacons, this.scrollController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (beacons.isEmpty) return const _EmptyBeaconState();

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: beacons.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _BeaconTile(beacon: beacons[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _EmptyBeaconState extends StatelessWidget {
  const _EmptyBeaconState();
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching,
                size: 44, color: AppTheme.textSecondary.withAlpha(100)),
            const SizedBox(height: 12),
            Text(
              'No beacons detected.\nEnsure Bluetooth is on and beacons are powered.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _BeaconTile extends ConsumerStatefulWidget {
  final BleBeacon beacon;
  const _BeaconTile({required this.beacon});

  @override
  ConsumerState<_BeaconTile> createState() => _BeaconTileState();
}

class _BeaconTileState extends ConsumerState<_BeaconTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final b = widget.beacon;

    // Fetch Firestore content to use objectName as the card title.
    final contentAsync = ref.watch(beaconContentProvider(b.macAddress));

    final String displayName = contentAsync.when(
      data: (content) {
        if (content != null && content.objectName.isNotEmpty) {
          return content.objectName;
        }
        return VenueConfig.beaconNames[b.macAddress] ??
            VenueConfig.beaconNames[b.deviceName] ??
            (b.deviceName.isNotEmpty ? b.deviceName : 'Unknown Exhibit');
      },
      loading: () =>
          VenueConfig.beaconNames[b.macAddress] ??
          VenueConfig.beaconNames[b.deviceName] ??
          'Loading…',
      error: (_, __) =>
          VenueConfig.beaconNames[b.macAddress] ?? 'Unknown Exhibit',
    );

    final content = contentAsync.valueOrNull;
    final String imageUrl = content?.imageUrl ?? '';
    final String videoUrl = content?.videoUrl ?? '';
    
    final isNear = b.isNear;
    final dist   = b.distanceMetres;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: isNear ? 4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header row ─────────────────────────────────────────────
              Row(
                children: [
                  // ── Image or Bluetooth icon container ─────────────────────
                  Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(
                      color: (isNear ? AppTheme.accentColor : AppTheme.primaryColor)
                          .withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, __) => Icon(
                              Icons.bluetooth,
                              color: isNear ? AppTheme.accentColor : AppTheme.primaryColor,
                              size: 24,
                            ),
                            errorWidget: (_, __, ___) => Icon(
                              Icons.bluetooth,
                              color: isNear ? AppTheme.accentColor : AppTheme.primaryColor,
                              size: 24,
                            ),
                          )
                        : Icon(
                            Icons.bluetooth,
                            color: isNear
                                ? AppTheme.accentColor
                                : AppTheme.primaryColor,
                            size: 24,
                          ),
                  ),
                  const SizedBox(width: 12),

                  // ── Exhibit name ──────────────────────────────────────
                  Expanded(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // ── Distance badge ────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${dist.toStringAsFixed(1)}m',
                        style: TextStyle(
                          color: isNear
                              ? AppTheme.accentColor
                              : AppTheme.primaryColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      if (isNear)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentColor,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: const Text(
                            'NEAR',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5),
                          ),
                        ),
                    ],
                  ),

                  // ── Video Button & Expand arrow ─────────────────────────
                  const SizedBox(width: 8),
                  if (videoUrl.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill,
                          color: AppTheme.primaryColor, size: 26),
                      tooltip: 'Watch Video',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        final uri = Uri.parse(videoUrl);
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.textSecondary,
                    size: 20,
                  ),
                ],
              ),

              // ── Signal strength bar ─────────────────────────────────────
              const SizedBox(height: 10),
              _SignalBar(rssi: b.filteredRssi),

              // ── Expanded content panel ──────────────────────────────────
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: _BeaconContentPanel(beacon: b),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signal strength bar (replaces _RssiBar)
// ─────────────────────────────────────────────────────────────────────────────

class _SignalBar extends StatelessWidget {
  final double rssi;
  const _SignalBar({required this.rssi});

  @override
  Widget build(BuildContext context) {
    final pct   = ((rssi + 90) / 60).clamp(0.0, 1.0);
    final color = Color.lerp(Colors.red.shade300, AppTheme.primaryColor, pct)!;
    return Row(
      children: [
        Icon(Icons.signal_cellular_alt, size: 13, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
              minHeight: 5,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '${rssi.toStringAsFixed(0)} dBm',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded panel: Firestore content + Gemini LLM narrative + TTS
// ─────────────────────────────────────────────────────────────────────────────

class _BeaconContentPanel extends ConsumerStatefulWidget {
  final BleBeacon beacon;
  const _BeaconContentPanel({required this.beacon});

  @override
  ConsumerState<_BeaconContentPanel> createState() => _BeaconContentPanelState();
}

class _BeaconContentPanelState extends ConsumerState<_BeaconContentPanel> {
  bool _showDeepDive = false;

  @override
  Widget build(BuildContext context) {
    final contentAsync = ref.watch(beaconContentProvider(widget.beacon.macAddress));
    final llmAsync = _showDeepDive 
        ? ref.watch(llmBeaconDeepDiveProvider(widget.beacon))
        : ref.watch(llmBeaconProvider(widget.beacon));
    final language = ref.watch(languageProvider).language;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),

        // ── Raw Firestore content ──────────────────────────────────────────
        contentAsync.when(
          loading: () => const _SmallSpinner(),
          error:   (e, _) => Text('Error loading content: $e',
              style: const TextStyle(color: Colors.red, fontSize: 12)),
          data: (content) => content == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No exhibit content found in Firestore.\n'
                    'Add a document keyed by MAC address to the "beacons" collection.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : _RawBeaconContent(content: content),
        ),

        const SizedBox(height: 14),

        // ── Gemini LLM narrative ───────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppTheme.primaryColor, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Gemini Guide',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                  ),
                  const Spacer(),
                  llmAsync.when(
                    data: (text) => text.isEmpty
                        ? const SizedBox()
                        : _TtsIconButton(text: text, language: language),
                    loading: () => const SizedBox(),
                    error:   (_, __) => const SizedBox(),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              llmAsync.when(
                loading: () => const Row(children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.primaryColor),
                  ),
                  SizedBox(width: 8),
                  Text('Generating…',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                ]),
                error: (e, _) => Text(
                  '$e',
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
                data: (text) => text.isEmpty
                    ? const Text(
                        'Configure your Gemini API key in lib/app/constants.dart '
                        'to see AI-generated narratives.',
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MarkdownBody(
                            data: text,
                            styleSheet:
                                MarkdownStyleSheet.fromTheme(Theme.of(context))
                                    .copyWith(
                              p: Theme.of(context).textTheme.bodyMedium,
                            ),
                            onTapLink: (_, href, __) async {
                              if (href != null) {
                                final uri = Uri.parse(href);
                                if (await canLaunchUrl(uri)) launchUrl(uri);
                              }
                            },
                          ),
                          if (!_showDeepDive) ...[
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.primaryColor,
                                  side: const BorderSide(color: AppTheme.primaryColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => setState(() => _showDeepDive = true),
                                child: const Text('Know More'),
                              ),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _RawBeaconContent extends StatelessWidget {
  final BeaconContent content;
  const _RawBeaconContent({required this.content});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content.objectName,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (content.imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: content.imageUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 180,
                  color: AppTheme.primaryColor.withAlpha(20),
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const SizedBox(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (content.description.isNotEmpty) ...[
            Text(content.description,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
          ],
          if (content.history.isNotEmpty) ...[
            Text(content.history,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 6),
          ],
          if (content.videoUrl.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.play_circle_outline,
                  color: AppTheme.primaryColor, size: 16),
              label: const Text('Watch Video'),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  padding: EdgeInsets.zero),
              onPressed: () async {
                final uri = Uri.parse(content.videoUrl);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _TtsIconButton extends StatefulWidget {
  final String text;
  final String language;
  const _TtsIconButton({required this.text, required this.language});

  @override
  State<_TtsIconButton> createState() => _TtsIconButtonState();
}

class _TtsIconButtonState extends State<_TtsIconButton> {
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
  Widget build(BuildContext context) => GestureDetector(
        onTap: _toggle,
        child: Icon(
          _playing ? Icons.stop_circle : Icons.play_circle_outline,
          color: AppTheme.primaryColor,
          size: 22,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();
  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.primaryColor),
        ),
      );
}
