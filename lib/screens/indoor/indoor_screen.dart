import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../models/floor_model.dart';
import '../../providers/ble_provider.dart';
import '../../providers/floor_provider.dart';
import '../../services/content_service.dart';
import 'floor_overlay_painter.dart';
import 'widgets/beacon_list_widget.dart';
import '../../widgets/language_picker_button.dart';

class IndoorScreen extends ConsumerStatefulWidget {
  const IndoorScreen({super.key});

  @override
  ConsumerState<IndoorScreen> createState() => _IndoorScreenState();
}

class _IndoorScreenState extends ConsumerState<IndoorScreen> {
  bool _isRefreshing = false;
  bool _isMapHidden = false;
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  // Background sync timer removed in favor of initial sync

  @override
  void initState() {
    super.initState();
    _performInitialSync();
    _sheetController.addListener(_onSheetChanged);
  }

  void _onSheetChanged() {
    if (!mounted) return;
    final size = _sheetController.size;
    final isHidden = size >= 0.9;
    if (_isMapHidden != isHidden) {
      setState(() {
        _isMapHidden = isHidden;
      });
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _toggleMap() {
    setState(() {
      _isMapHidden = !_isMapHidden;
    });
    // Animate the sheet: 1.0 hides the map entirely, 0.5 shows half map.
    _sheetController.animateTo(
      _isMapHidden ? 1.0 : 0.5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  // ── Initial Firestore sync ──────────────────────────────────────────────────

  Future<void> _performInitialSync() async {
    // 1. Fetch all beacons and floor plans once when the indoor screen opens.
    try {
      await Future.wait([
        ContentService.preCacheVenueBeacons(),
        ContentService.refreshFloorConfigs(),
      ]);

      if (mounted) {
        ref.invalidate(floorsProvider);
        ref.invalidate(floorBeaconsProvider);
      }
    } catch (_) {
      // Silently fail, it will fall back to SQLite cache
    }
  }

  /// Force-refreshes all floor data and beacons from Firestore:
  ///  1. Wipes the SQLite floors and beacons cache
  ///  2. Re-fetches floors and beacons from Firestore
  ///  3. Invalidates all floor providers so UI rebuilds with fresh data
  Future<void> _onRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      // 1. Force-fetch floors from Firestore and overwrite SQLite.
      await ContentService.refreshFloorConfigs();
      // 1.5 Force-fetch beacons from Firestore and overwrite SQLite.
      await ContentService.forceRefreshBeacons();

      // 2. Invalidate providers so they re-run with new data.
      ref.invalidate(floorsProvider);
      ref.invalidate(floorBeaconsProvider);

      // 3. Re-detect current floor with fresh data.
      await ref.read(currentFloorProvider.notifier).refreshFloors();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Floor plan and exhibits refreshed ✓'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bleState     = ref.watch(bleProvider);
    final floorsAsync  = ref.watch(floorsProvider);
    final currentFloor = ref.watch(currentFloorProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentFloor?.displayName ?? 'Indoor Navigation'),
        actions: [
          // Refresh floor data from Firestore
          _isRefreshing
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh floor plan and exhibits',
                  onPressed: _onRefresh,
                ),
          // Toggle map button
          IconButton(
            icon: Icon(_isMapHidden ? Icons.map : Icons.map_outlined),
            tooltip: _isMapHidden ? 'Show Map' : 'Hide Map',
            onPressed: _toggleMap,
          ),
          // BLE scan toggle
          IconButton(
            icon: Icon(bleState.isScanning
                ? Icons.bluetooth_searching
                : Icons.bluetooth_disabled),
            color: bleState.isScanning
                ? AppTheme.primaryColor
                : AppTheme.textSecondary,
            tooltip: bleState.isScanning ? 'Stop scan' : 'Start scan',
            onPressed: () {
              if (bleState.isScanning) {
                ref.read(bleProvider.notifier).stopScan();
              } else {
                ref.read(bleProvider.notifier).startScan();
              }
            },
          ),
          const LanguagePickerButton(),
        ],
      ),
      body: Column(
        children: [
          // ── Floor selector tabs ──────────────────────────────────────────
          floorsAsync.when(
            data: (floors) => floors.length > 1
                ? _FloorSelector(floors: floors, currentFloor: currentFloor)
                : const SizedBox.shrink(),
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
          ),

          // ── BLE Status bar ───────────────────────────────────────────────
          _StatusBar(bleState: bleState, currentFloor: currentFloor),

          // ── Floor plan map & Draggable Exhibits ──────────────────────────────
          Expanded(
            child: Stack(
              children: [
                // 1. The Map (Background)
                Positioned.fill(
                  child: currentFloor == null
                      ? _NoFloorPlaceholder(bleState: bleState)
                      : _FloorMapView(floor: currentFloor, bleState: bleState),
                ),

                // 2. The Draggable Exhibits List (Foreground)
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: 0.5,
                  minChildSize: 0.05, // Can slide down almost completely to see full map
                  maxChildSize: 1.0,  // Can slide up to take full screen
                  snap: true,
                  snapSizes: const [0.05, 0.5, 1.0],
                  builder: (context, scrollController) {
                    return Container(
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -4))
                        ],
                      ),
                      child: Column(
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 10),
                              width: 48,
                              height: 5,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade400,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          // The Exhibits List
                          Expanded(
                            child: BeaconListWidget(
                              beacons: bleState.sortedBeacons,
                              scrollController: scrollController,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floor selector tab strip
// ─────────────────────────────────────────────────────────────────────────────

class _FloorSelector extends ConsumerWidget {
  final List<FloorConfig> floors;
  final FloorConfig? currentFloor;
  const _FloorSelector({required this.floors, required this.currentFloor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color:  AppTheme.cardColor,
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: floors.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final floor    = floors[i];
          final isActive = currentFloor?.id == floor.id;
          return GestureDetector(
            onTap: () =>
                ref.read(currentFloorProvider.notifier).setFloor(floor),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: isActive
                    ? AppTheme.primaryColor
                    : AppTheme.primaryColor.withAlpha(20),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                floor.displayName,
                style: TextStyle(
                  color: isActive ? Colors.white : AppTheme.primaryColor,
                  fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final BleState    bleState;
  final FloorConfig? currentFloor;
  const _StatusBar({required this.bleState, required this.currentFloor});

  @override
  Widget build(BuildContext context) {
    final confirmedCount = bleState.sortedBeacons.length;
    final totalCount     = bleState.detectedBeacons.length;

    return Container(
      color:   AppTheme.cardColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.bluetooth,
            size:  14,
            color: totalCount > 0
                ? AppTheme.accentColor
                : AppTheme.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            totalCount > 0
                ? '$confirmedCount confirmed near  •  $totalCount detected'
                : 'Searching for beacons…',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontSize: 12),
          ),
          const Spacer(),
          if (currentFloor != null)
            Text(
              currentFloor!.displayName,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize:   12,
                    color:      AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floor map: image + overlay stack
// ─────────────────────────────────────────────────────────────────────────────

class _FloorMapView extends ConsumerStatefulWidget {
  final FloorConfig floor;
  final BleState    bleState;
  const _FloorMapView({required this.floor, required this.bleState});

  @override
  ConsumerState<_FloorMapView> createState() => _FloorMapViewState();
}

class _FloorMapViewState extends ConsumerState<_FloorMapView>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final floor             = widget.floor;
    final bleState          = widget.bleState;
    final floorBeaconsAsync = ref.watch(floorBeaconsProvider(floor.id));

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      boundaryMargin: const EdgeInsets.all(60),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final containerW = constraints.maxWidth;
          final containerH = constraints.maxHeight;

          // ── Compute exact rendered image size (BoxFit.contain logic) ────────
          // We replicate Flutter's BoxFit.contain math so the painter gets
          // the exact same pixel bounds as the image widget.
          final imgAspect       = floor.imageWidthPixels / floor.imageHeightPixels;
          final containerAspect = containerW / containerH;

          final double imgRenderW;
          final double imgRenderH;

          if (containerAspect < imgAspect) {
            // Container is narrower → width is the limiting dimension.
            imgRenderW = containerW;
            imgRenderH = containerW / imgAspect;
          } else {
            // Container is wider → height is the limiting dimension.
            imgRenderH = containerH;
            imgRenderW = containerH * imgAspect;
          }

          // Centre horizontally, pin to top (matches Alignment.topCenter).
          final offsetX = (containerW - imgRenderW) / 2;
          const offsetY = 0.0;

          final paintSize = Size(imgRenderW, imgRenderH);

          return Stack(
            children: [
              // ── Layer 1: Floor plan PNG — sized exactly ──────────────────
              Positioned(
                left:   offsetX,
                top:    offsetY,
                width:  imgRenderW,
                height: imgRenderH,
                child: Builder(
                  builder: (_) {
                    debugPrint('[FloorMap] Loading: ${floor.imageUrl}');
                    return Image.network(
                      floor.imageUrl,
                      width:  imgRenderW,
                      height: imgRenderH,
                      fit:    BoxFit.fill,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child; // fully loaded
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (_, error, __) {
                        debugPrint('[FloorMap] ❌ Image.network error: $error');
                        debugPrint('[FloorMap]    URL: ${floor.imageUrl}');
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image_outlined,
                                  size: 48, color: AppTheme.textSecondary),
                              const SizedBox(height: 8),
                              const Text('Floor plan unavailable',
                                  style: TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'Error: $error',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary,
                                      fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // ── Layer 2: Beacon overlay — identical Positioned bounds ─────
              Positioned(
                left:   offsetX,
                top:    offsetY,
                width:  imgRenderW,
                height: imgRenderH,
                child: floorBeaconsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error:   (_, __) => const SizedBox.shrink(),
                  data: (beacons) => AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: FloorOverlayPainter(
                          floorConfig:     floor,
                          floorBeacons:    beacons,
                          detectedBeacons: bleState.detectedBeacons,
                          renderedSize:    paintSize,
                          pulseValue:      _pulseController.value,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Placeholder when no floor auto-detected yet
// ─────────────────────────────────────────────────────────────────────────────

class _NoFloorPlaceholder extends StatelessWidget {
  final BleState bleState;
  const _NoFloorPlaceholder({required this.bleState});

  @override
  Widget build(BuildContext context) {
    final beaconCount = bleState.detectedBeacons.length;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined,
              size:  52,
              color: AppTheme.textSecondary.withAlpha(100)),
          const SizedBox(height: 16),
          Text(
            beaconCount > 0
                ? 'Detecting floor… ($beaconCount beacon${beaconCount > 1 ? "s" : ""} found)'
                : 'Walk near a beacon to load the floor plan.',
            textAlign: TextAlign.center,
            style:     Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
