import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../app/theme.dart';
import '../../providers/app_text_provider.dart';
import '../../providers/outdoor_provider.dart';
import '../../providers/location_mode_provider.dart';
import 'widgets/place_card.dart';
import '../../widgets/language_picker_button.dart';

class OutdoorScreen extends ConsumerStatefulWidget {
  const OutdoorScreen({super.key});

  @override
  ConsumerState<OutdoorScreen> createState() => _OutdoorScreenState();
}

class _OutdoorScreenState extends ConsumerState<OutdoorScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final PageController _pageController = PageController(viewportFraction: 0.9);

  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(outdoorProvider.notifier).initialise();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _moveCameraToPlace(double lat, double lng) async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
  }

  @override
    Widget build(BuildContext context) {
      final state = ref.watch(outdoorProvider);
      final modeState = ref.watch(locationModeProvider);

    final initialCameraPosition = CameraPosition(
      target: state.userPosition != null
          ? LatLng(state.userPosition!.latitude, state.userPosition!.longitude)
          : const LatLng(0, 0), // Default if GPS is not yet acquired
      zoom: 16.0,
    );

    // Create map markers from the places
    final Set<Marker> markers = state.places.asMap().entries.map((entry) {
      final index = entry.key;
      final place = entry.value;
      return Marker(
        markerId: MarkerId(place.id),
        position: LatLng(place.lat, place.lng),
        infoWindow: InfoWindow(title: place.name, snippet: place.category),
        onTap: () {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        },
      );
    }).toSet();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(ref.watch(appTextProvider(('outdoor_explorer', 'Outdoor Explorer')))),
        backgroundColor: Colors.white.withAlpha(220),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Re-center on me',
            onPressed: () async {
              if (state.userPosition != null) {
                final controller = await _controller.future;
                controller.animateCamera(CameraUpdate.newLatLngZoom(
                  LatLng(state.userPosition!.latitude,
                      state.userPosition!.longitude),
                  16.0,
                ));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: ref.watch(appTextProvider(('refresh', 'Refresh'))),
            onPressed: () => ref.read(outdoorProvider.notifier).refresh(),
          ),
          const LanguagePickerButton(),
        ],
      ),
      body: state.isLocating
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(ref.watch(appTextProvider(('acquiring_gps', 'Acquiring GPS location…')))),
                ],
              ),
            )
          : Stack(
              children: [
                // ── Google Map ───────────────────────────────────────────
                GoogleMap(
                  initialCameraPosition: initialCameraPosition,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  markers: markers,
                  onMapCreated: (GoogleMapController controller) {
                    if (!_controller.isCompleted) {
                      _controller.complete(controller);
                    }
                  },
                ),

                // ── Top Radius Slider Banner ──────────────────────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(240),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
                      ],
                    ),
                    child: _RadiusBar(
                      radius: state.searchRadius,
                      onChanged: (v) => ref.read(outdoorProvider.notifier).updateRadius(v),
                    ),
                  ),
                ),

                // ── GPS Accuracy Floating Chip ───────────────────────────
                Positioned(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 85,
                  right: 24,
                  child: _AccuracyBadge(accuracy: modeState.gpsAccuracy),
                ),

                // ── Status Overlays ────────────────────────────────────────
                if (state.isLoadingPlaces)
                  Center(
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 16),
                            Text(ref.watch(appTextProvider(('loading_places', 'Loading places…')))),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (state.errorMessage != null)
                  Center(
                    child: Card(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          state.errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),

                // ── Bottom Carousel ────────────────────────────────────────
                if (state.places.isNotEmpty)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      height: 140, // Height for the place card carousel
                      margin: const EdgeInsets.only(bottom: 24),
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: state.places.length,
                        onPageChanged: (index) {
                          setState(() => _currentIndex = index);
                          final place = state.places[index];
                          _moveCameraToPlace(place.lat, place.lng);
                        },
                        itemBuilder: (context, index) {
                          // Scale effect for the focused card
                          final itemScale = _currentIndex == index ? 1.0 : 0.9;
                          return TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 200),
                            tween: Tween(begin: itemScale, end: itemScale),
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: child,
                              );
                            },
                            child: PlaceCard(place: state.places[index]),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _RadiusBar extends StatelessWidget {
  final double radius;
  final ValueChanged<double> onChanged;
  
  // Discrete steps for the radius
  static const List<double> steps = [100, 250, 500, 1000, 2000, 3000, 5000, 10000];
  
  const _RadiusBar({required this.radius, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // Find closest step index to current radius
    int currentIndex = steps.indexWhere((s) => s >= radius);
    if (currentIndex == -1) currentIndex = steps.length - 1;
    
    // Format the display label
    String displayLabel = radius >= 1000
        ? '${(radius / 1000).toStringAsFixed(radius % 1000 == 0 ? 0 : 1)}km'
        : '${radius.round()}m';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Keep banner small vertically
        children: [
          const Icon(Icons.radar, color: AppTheme.primaryColor, size: 24),
          const SizedBox(width: 8),
          Text(
            'Radius: $displayLabel',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              ),
              child: Slider(
                value: currentIndex.toDouble(),
                min: 0,
                max: (steps.length - 1).toDouble(),
                divisions: steps.length - 1,
                activeColor: AppTheme.primaryColor,
                inactiveColor: AppTheme.primaryColor.withAlpha(60),
                onChanged: (val) {
                  onChanged(steps[val.toInt()]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccuracyBadge extends StatelessWidget {
  final double accuracy;
  const _AccuracyBadge({required this.accuracy});

  @override
  Widget build(BuildContext context) {
    // Determine color based on quality (Green < 12m, Orange < 25m, Red >= 25m)
    final Color color = accuracy < 12 ? Colors.green : (accuracy < 25 ? Colors.orange : Colors.red);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.gps_fixed, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            'Accuracy: ±${accuracy.round()}m',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
