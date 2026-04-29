import 'package:geolocator/geolocator.dart';

/// Handles GPS permission requests and returns the current device position.
///
/// Think of this as the app's "GPS antenna manager" — it checks if the
/// antenna is on, asks the user to allow it if not, then gets the reading.
class LocationService {
  static Future<Position> getCurrentLocation() async {
    // Step 1: Is the phone's GPS/Location setting turned on at all?
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Location services are disabled. Please turn on GPS.');
    }

    // Step 2: Has the user granted permission to this app?
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Show the OS permission dialog once.
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permission denied.');
      }
    }

    // Step 3: Has the user permanently blocked location for this app?
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
          'Location permission permanently denied. Enable it in Settings → App Permissions.');
    }

    // Step 4: Get the actual GPS fix.
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  /// Returns a stream of position updates (for future live tracking).
  static Stream<Position> getPositionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // update every 5 metres
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }
}
