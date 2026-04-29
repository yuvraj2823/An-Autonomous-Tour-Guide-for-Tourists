import 'package:flutter_riverpod/flutter_riverpod.dart';


/// Immutable indoor state.
///
/// Simplified in v5: PDR and EKF removed.
/// The floor plan is driven purely by BLE beacon proximity detection.
class IndoorState {
  const IndoorState();
}

class IndoorNotifier extends StateNotifier<IndoorState> {
  IndoorNotifier() : super(const IndoorState());
}

final indoorProvider =
    StateNotifierProvider<IndoorNotifier, IndoorState>(
  (ref) => IndoorNotifier(),
);
