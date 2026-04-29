import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/place_model.dart';
import '../screens/shell_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/outdoor/outdoor_screen.dart';
import '../screens/indoor/indoor_screen.dart';
import '../screens/place_detail/place_detail_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      // ── Shell (tabs with BottomNavigationBar) ─────────────────────────
      ShellRoute(
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/outdoor', builder: (_, __) => const OutdoorScreen()),
          GoRoute(path: '/indoor', builder: (_, __) => const IndoorScreen()),
        ],
      ),
      // ── PlaceDetailScreen outside ShellRoute → no bottom nav bar ──────
      GoRoute(
        path: '/place-detail',
        builder: (context, state) {
          final place = state.extra as Place;
          return PlaceDetailScreen(place: place);
        },
      ),
    ],
  );
});
