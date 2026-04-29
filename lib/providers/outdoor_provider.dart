import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../models/place_model.dart';
import '../services/location_service.dart';
import '../services/firestore_service.dart';
import '../app/constants.dart';

/// Immutable state for the outdoor tab.
class OutdoorState {
  final bool isLocating;
  final bool isLoadingPlaces;
  final Position? userPosition;
  final List<Place> places;
  final double searchRadius;
  final String? errorMessage;

  const OutdoorState({
    this.isLocating       = false,
    this.isLoadingPlaces  = false,
    this.userPosition,
    this.places           = const [],
    this.searchRadius     = AppConstants.defaultSearchRadius,
    this.errorMessage,
  });

  OutdoorState copyWith({
    bool?     isLocating,
    bool?     isLoadingPlaces,
    Position? userPosition,
    List<Place>? places,
    double?   searchRadius,
    String?   errorMessage,
    bool      clearError = false,
  }) =>
      OutdoorState(
        isLocating:      isLocating      ?? this.isLocating,
        isLoadingPlaces: isLoadingPlaces ?? this.isLoadingPlaces,
        userPosition:    userPosition    ?? this.userPosition,
        places:          places          ?? this.places,
        searchRadius:    searchRadius    ?? this.searchRadius,
        errorMessage:    clearError ? null : (errorMessage ?? this.errorMessage),
      );
}

class OutdoorNotifier extends StateNotifier<OutdoorState> {
  OutdoorNotifier() : super(const OutdoorState());

  /// Get GPS fix, then load places from Firestore.
  Future<void> initialise() async {
    state = state.copyWith(isLocating: true, clearError: true);
    try {
      final position = await LocationService.getCurrentLocation();
      state = state.copyWith(isLocating: false, userPosition: position);
      await _fetchPlaces(position);
    } catch (e) {
      state = state.copyWith(
        isLocating:   false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Fetch all places from Firestore, compute distances, filter, and sort.
  Future<void> _fetchPlaces(Position position) async {
    state = state.copyWith(isLoadingPlaces: true, clearError: true);
    try {
      final docs = await FirestoreService.getAllPlaceDocuments();
      final all = docs
          .map((d) => Place.fromFirestore(d['id'] as String, d, position.latitude, position.longitude))
          .toList();

      // Filter by user-configured search radius.
      final filtered = all
          .where((p) => p.distanceMetres <= state.searchRadius)
          .toList();

      // Sort nearest first.
      filtered.sort((a, b) => a.distanceMetres.compareTo(b.distanceMetres));

      state = state.copyWith(isLoadingPlaces: false, places: filtered);
    } catch (e) {
      state = state.copyWith(
        isLoadingPlaces: false,
        errorMessage:    e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Update search radius and re-filter the currently loaded places.
  Future<void> updateRadius(double newRadius) async {
    state = state.copyWith(searchRadius: newRadius);
    if (state.userPosition != null) await _fetchPlaces(state.userPosition!);
  }

  /// Refresh places without re-acquiring GPS (GPS position stays the same).
  Future<void> refresh() async {
    if (state.userPosition != null) {
      await _fetchPlaces(state.userPosition!);
    } else {
      await initialise();
    }
  }
}

final outdoorProvider =
    StateNotifierProvider<OutdoorNotifier, OutdoorState>(
  (ref) => OutdoorNotifier(),
);
