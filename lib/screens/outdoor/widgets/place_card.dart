import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/theme.dart';
import '../../../models/place_model.dart';
import '../../../providers/content_provider.dart';

/// A card representing one outdoor place, used in the bottom carousel on the map.
/// Tapping navigates to PlaceDetailScreen via go_router.
class PlaceCard extends ConsumerWidget {
  final Place place;
  const PlaceCard({super.key, required this.place});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fetch enriched Firestore content for images & video URLs.
    final contentAsync = ref.watch(placeContentProvider(place.id));
    final content = contentAsync.valueOrNull;

    final String imageUrl = content?.imageUrl ?? '';
    final String videoUrl = content?.videoUrl ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/place-detail', extra: place),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Thumbnail or Category icon ────────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.hardEdge,
                child: imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) =>
                            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        errorWidget: (context, url, error) => Icon(
                          _categoryIcon(place.category),
                          color: AppTheme.primaryColor,
                          size: 32,
                        ),
                      )
                    : Icon(
                        _categoryIcon(place.category),
                        color: AppTheme.primaryColor,
                        size: 32,
                      ),
              ),
              const SizedBox(width: 14),

              // ── Place info ────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      place.name,
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _Chip(label: place.category, color: AppTheme.primaryColor),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            place.vicinity,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (place.rating != null) ...[
                          const Icon(Icons.star_rounded,
                              color: AppTheme.accentColor, size: 16),
                          const SizedBox(width: 2),
                          Text(
                            place.rating!.toStringAsFixed(1),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Text(
                          place.formattedDistance,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Right side actions (Video button + chevron) ───────────
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (videoUrl.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.play_circle_fill,
                          color: AppTheme.primaryColor, size: 28),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Watch Video',
                      onPressed: () async {
                        final uri = Uri.parse(videoUrl);
                        if (await canLaunchUrl(uri)) await launchUrl(uri);
                      },
                    )
                  else
                    const SizedBox(height: 28), // balance height
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right,
                      color: AppTheme.textSecondary, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'museum':           return Icons.museum;
      case 'art gallery':      return Icons.palette;
      case 'mosque':           return Icons.mosque;
      case 'temple':           return Icons.temple_hindu;
      case 'church':           return Icons.church;
      case 'park':             return Icons.park;
      case 'university':       return Icons.school;
      case 'shopping mall':    return Icons.shopping_bag;
      case 'hotel':            return Icons.hotel;
      case 'library':          return Icons.local_library;
      default:                 return Icons.place;
    }
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}
