import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../app/constants.dart';
import '../app/theme.dart';
import '../providers/location_mode_provider.dart';
import '../providers/ble_provider.dart';
import '../providers/app_text_provider.dart';

/// Persistent shell wrapping the three tab screens (Home / Outdoor / Indoor).
///
/// Responsibilities:
///  1. Start BLE scanning on app launch (always-on).
///  2. Start the Seamless Transition Engine.
///  3. Auto-navigate between /outdoor and /indoor when the engine changes mode.
///  4. Show a slim status banner indicating the current mode.
class ShellScreen extends ConsumerStatefulWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  bool _started = false;
  
  bool _btOn = true; // Assume true until verified to avoid brief flicker
  bool _locOn = true;

  StreamSubscription<BluetoothAdapterState>? _btSub;
  StreamSubscription<ServiceStatus>? _locSub;

  @override
  void initState() {
    super.initState();
    _checkInitialServices();
  }

  Future<void> _checkInitialServices() async {
    // 1. Listen to Bluetooth status
    _btSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() {
           _btOn = state == BluetoothAdapterState.on;
        });
        _checkAndStart();
      }
    });

    // 2. Check initial Location status and listen for changes
    final locInit = await Geolocator.isLocationServiceEnabled();
    if (mounted) {
       setState(() { _locOn = locInit; });
    }
    _locSub = Geolocator.getServiceStatusStream().listen((status) {
      if (mounted) {
        setState(() {
           _locOn = status == ServiceStatus.enabled;
        });
        _checkAndStart();
      }
    });

    _checkAndStart();
  }

  void _checkAndStart() {
    if (_btOn && _locOn && !_started) {
      // Both services are on and we haven't started yet!
      WidgetsBinding.instance.addPostFrameCallback((_) => _startPipeline());
    }
  }

  Future<void> _startPipeline() async {
    if (_started) return;
    _started = true;

    // 1. BLE always-on — drives the transition engine.
    await ref.read(bleProvider.notifier).startScan();

    // 2. Start the transition engine (GPS polling + evidence accumulator).
    ref.read(locationModeProvider.notifier).startEngine();

    // 3. Auto-route to the correct screen on app launch.
    if (mounted) {
      final mode = ref.read(locationModeProvider).mode;
      if (mode == LocationMode.indoor) {
        context.go('/indoor');
      } else {
        context.go('/outdoor');
      }
    }
  }

  @override
  void dispose() {
    _btSub?.cancel();
    _locSub?.cancel();
    if (_started) {
      ref.read(bleProvider.notifier).stopScan();
      ref.read(locationModeProvider.notifier).stopEngine();
    }
    super.dispose();
  }

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/outdoor')) return 1;
    if (location.startsWith('/indoor'))  return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!_btOn || !_locOn) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 64, color: AppTheme.primaryColor),
                const SizedBox(height: 16),
                const Text(
                  'Services Required',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                const Text(
                  'The Seamless Tour Guide requires both Bluetooth and Location services to be enabled to automatically switch between indoor and outdoor modes.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 48),
                if (!_btOn) ...[
                  ElevatedButton.icon(
                    onPressed: () async {
                      if (Platform.isAndroid) {
                        try {
                          await FlutterBluePlus.turnOn();
                        } catch (e) {
                          debugPrint('Could not turn on BT: $e');
                        }
                      }
                    },
                    icon: const Icon(Icons.bluetooth),
                    label: Text(Platform.isAndroid ? 'Turn on Bluetooth' : 'Please enable Bluetooth in Control Center'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_locOn)
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Geolocator.openLocationSettings();
                    },
                    icon: const Icon(Icons.location_on),
                    label: const Text('Turn on Location'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    final modeState = ref.watch(locationModeProvider);

    // ── Auto-navigate when engine changes mode ──────────────────────────────
    ref.listen<LocationModeState>(locationModeProvider, (prev, next) {
      if (prev?.mode == next.mode) return;
      if (!context.mounted) return;

      switch (next.mode) {
        case LocationMode.indoor:
          // Only auto-switch if the user is not already on indoor tab.
          final loc = GoRouterState.of(context).uri.toString();
          if (!loc.startsWith('/indoor')) {
            context.go('/indoor');
          }
          break;
        case LocationMode.outdoor:
          final loc = GoRouterState.of(context).uri.toString();
          if (!loc.startsWith('/outdoor')) {
            context.go('/outdoor');
          }
          break;
        case LocationMode.transitioning:
          // Stay on current screen during transition buffer.
          break;
      }
    });

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeBanner(modeState: modeState),
          BottomNavigationBar(
            currentIndex: _currentIndex(context),
            onTap: (index) {
              switch (index) {
                case 0: context.go('/');        break;
                case 1: context.go('/outdoor'); break;
                case 2: context.go('/indoor');  break;
              }
            },
            items: [
              BottomNavigationBarItem(
                icon: const Icon(Icons.home_outlined),
                activeIcon: const Icon(Icons.home),
                label: ref.watch(appTextProvider(('home', 'Home'))),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.explore_outlined),
                activeIcon: const Icon(Icons.explore),
                label: ref.watch(appTextProvider(('outdoor', 'Outdoor'))),
              ),
              BottomNavigationBarItem(
                icon: const Icon(Icons.location_city_outlined),
                activeIcon: const Icon(Icons.location_city),
                label: ref.watch(appTextProvider(('indoor', 'Indoor'))),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Mode Banner ────────────────────────────────────────────────────────────

class _ModeBanner extends ConsumerWidget {
  final LocationModeState modeState;
  const _ModeBanner({required this.modeState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color    bgColor;
    final IconData icon;
    final String   label;

    switch (modeState.mode) {
      case LocationMode.outdoor:
        bgColor = AppTheme.primaryColor;
        icon    = Icons.satellite_alt;
        label   = modeState.statusMessage ??
            ref.watch(appTextProvider(('outdoor_mode_active', 'Outdoor Mode — GPS Active')));
        break;
      case LocationMode.indoor:
        bgColor = AppTheme.accentColor;
        icon    = Icons.bluetooth;
        label   = modeState.statusMessage ??
            ref.watch(appTextProvider(('indoor_mode_active', 'Indoor Mode — BLE Active')));
        break;
      case LocationMode.transitioning:
        final almostSure = modeState.evidenceScore >= (AppConstants.indoorEvidenceThreshold - 1.5);
        if (almostSure) {
          bgColor = Colors.orange.shade700;
          icon    = Icons.sync;
          label   = modeState.statusMessage ??
              ref.watch(appTextProvider(('switching_mode', 'Approaching venue…')));
        } else {
          bgColor = AppTheme.primaryColor;
          icon    = Icons.satellite_alt;
          label   = ref.watch(appTextProvider(('outdoor_mode_active', 'Outdoor Mode — GPS Active')));
        }
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: double.infinity,
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Spinning icon while transitioning
            if (modeState.mode == LocationMode.transitioning && modeState.evidenceScore >= (AppConstants.indoorEvidenceThreshold - 1.5))
              const _SpinIcon()
            else
              Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Evidence score during TRANSITIONING (debug aid)
            if (modeState.mode == LocationMode.transitioning)
              Text(
                'ev ${modeState.evidenceScore.toStringAsFixed(1)}'
                '/${AppConstants.indoorEvidenceThreshold.toStringAsFixed(0)}'
                '  ${modeState.transitionSecs}s',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10,
                ),
              ),
            // Beacon loss counter while in INDOOR (nearing exit)
            if (modeState.mode == LocationMode.indoor &&
                modeState.beaconLostSecs > 0)
              Text(
                'signal lost ${modeState.beaconLostSecs}s',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 10,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpinIcon extends StatefulWidget {
  const _SpinIcon();

  @override
  State<_SpinIcon> createState() => _SpinIconState();
}

class _SpinIconState extends State<_SpinIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _ctrl,
      child: const Icon(Icons.sync, color: Colors.white, size: 13),
    );
  }
}
