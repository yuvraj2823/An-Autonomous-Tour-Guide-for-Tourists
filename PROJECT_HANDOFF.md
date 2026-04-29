# AI Tour Guide App — Complete Project Handoff

> **For the new AI agent**: Read this entire document before touching any code.
> The workspace root is:
> `C:\Users\yuvra\.gemini\antigravity\scratch\tour_guide_app\`

---

## 1. Project Idea & Vision

An **AI-powered museum/venue tour guide** app that:
- Detects whether the user is **indoors or outdoors** automatically
- **Outdoors**: Uses GPS to detect nearby exhibits/places and reads out AI-generated narration about them
- **Indoors**: Uses **BLE (Bluetooth Low Energy) beacons** to detect nearby exhibits, shows the user's position on a **custom floor plan map**, and provides AI-generated audio narration about exhibits within 4 metres

The app replaces a human tour guide. The visitor just walks around — the app detects what they're near and tells them about it automatically.

### Content Philosophy
- Content is fetched from **Firebase Firestore** (static data) + **Gemini AI** (enriched narration)
- **Base mode**: 20-100 words (adjusts based on available info — short for a small cabin, longer for info-rich exhibits)
- **Deep dive / Know More**: Longer narration combining Firestore data + internet search
- **Never hallucinate**: If data is sparse, say less. Do not invent facts.
- **Indoor objects**: Only trigger narration if confirmed within **0-4 metres** (with noise filtering — requires 3 consecutive BLE hits before activating)

---

## 2. Tech Stack

| Layer | Tech |
|---|---|
| Framework | Flutter (Android) |
| State management | Riverpod (flutter_riverpod) |
| BLE | flutter_blue_plus |
| AI narration | Google Gemini (google_generative_ai) Flash model |
| Backend / DB | Firebase Firestore (metadata), Firebase Storage (images) |
| Local cache | SQLite via sqflite |
| Image loading | Image.network (switched from cached_network_image due to stale error caching) |
| Text-to-speech | flutter_tts |
| GPS | geolocator |
| Routing | go_router |

---

## 3. Project File Structure

```
lib/
├── main.dart
├── firebase_options.dart
├── app/
│   ├── constants.dart          <- ALL tuneable constants (thresholds, UUIDs, etc.)
│   ├── router.dart             <- go_router shell + routes
│   ├── theme.dart              <- AppTheme (colors, text styles)
│   └── venue_config.dart       <- ARCHIVED (replaced by Firestore data)
├── models/
│   ├── beacon_model.dart       <- BeaconContent (Firestore <-> SQLite)
│   ├── ble_beacon_model.dart   <- BleBeacon (live BLE scan data)
│   ├── floor_model.dart        <- FloorConfig (floor plan metadata)
│   ├── place_content_model.dart
│   └── place_model.dart
├── providers/
│   ├── ble_provider.dart       <- BleNotifier: scans BLE, Kalman filters RSSI
│   ├── floor_provider.dart     <- CurrentFloorNotifier + floorsProvider + floorBeaconsProvider
│   ├── indoor_provider.dart    <- Minimal (PDR/EKF was removed)
│   ├── content_provider.dart   <- AI narration provider
│   ├── language_provider.dart
│   ├── location_mode_provider.dart  <- Indoor/Outdoor mode switching
│   └── outdoor_provider.dart
├── screens/
│   ├── shell_screen.dart       <- Bottom nav + mode detection logic
│   ├── home/home_screen.dart
│   ├── indoor/
│   │   ├── indoor_screen.dart        <- MAIN indoor UI (floor map + beacon list)
│   │   ├── floor_overlay_painter.dart <- CustomPainter for beacon markers on map
│   │   ├── indoor_map_painter.dart   <- Legacy painter (unused, keep for reference)
│   │   └── widgets/beacon_list_widget.dart  <- Scrollable list of nearby beacons
│   ├── outdoor/outdoor_screen.dart
│   └── place_detail/place_detail_screen.dart
└── services/
    ├── content_service.dart    <- SQLite-first data access layer
    ├── database_service.dart   <- SQLite v5 schema + CRUD
    ├── firestore_service.dart  <- Firestore read methods
    ├── gemini_service.dart     <- Gemini API calls
    ├── tts_service.dart        <- Text-to-speech
    ├── location_service.dart   <- GPS
    ├── kalman_filter.dart      <- RSSI smoothing (used by BleNotifier)
    ├── ekf_filter.dart         <- Legacy EKF (unused, keep file)
    ├── madgwick_filter.dart    <- Legacy IMU filter (unused, keep file)
    └── pdr_engine.dart         <- Legacy PDR (unused, keep file)
```

---

## 4. Firebase Data Structure

### Firestore Collections

#### beacons collection
Each document = one physical BLE beacon / exhibit.
```
beacons/{docId}
  macAddress:    "0E:A5:26:34:00:04"   (UPPERCASE, colon-separated)
  objectName:    "Dr. Hiteshi Tandon's Cabin"
  description:   "Brief description..."
  floorId:       "abc123XYZ"  (= document ID in 'floors' collection)
  pixelX:        640.0        (x pixel coord in floor plan PNG, number type)
  pixelY:        320.0        (y pixel coord in floor plan PNG, number type)
  imageUrl:      "https://..."  (optional exhibit photo)
  category:      "office"
```

#### floors collection
Each document = one floor of the venue.
```
floors/{docId}
  floorNumber:       1
  displayName:       "3rd Floor"
  imageUrl:          "https://firebasestorage.googleapis.com/..."
  imageWidthPixels:  1280
  imageHeightPixels: 1707
```

CRITICAL: imageUrl must be the HTTPS Firebase Storage download URL (with ?alt=media&token=...).
NOT a gs:// path. The token in the URL grants public access regardless of Storage rules.

#### places collection
Outdoor GPS-based places (separate from indoor beacons).

### Firebase Storage
- Floor plan images stored under /floors/ folder
- After uploading, copy the Download URL from Firebase Console
- Paste into imageUrl field of the floors Firestore document

---

## 5. Key Architecture Decisions

### 5.1 Indoor/Outdoor Mode Switching
Defined in location_mode_provider.dart. Switching logic in shell_screen.dart.
- BLE beacons detected + GPS accuracy poor = Indoor mode
- GPS accuracy good + no BLE = Outdoor mode
- Confirmation buffer prevents flicker

### 5.2 BLE Beacon Detection
File: providers/ble_provider.dart

- Scans for beacons matching AppConstants.knownBeaconUuids
- MAC address = device.remoteId.str.toUpperCase() — used as key everywhere
- Kalman filter smooths noisy RSSI before converting to distance
- Distance formula: d = 10^((txPower - rssi) / (10 * n))
- BleBeacon.isConfirmedInRange = true only if consecutiveInRangeCount >= beaconConfirmationThreshold (3)
- BleState.sortedBeacons = only confirmed beacons <= 4m, sorted by distance

### 5.3 Floor Detection
File: providers/floor_provider.dart — CurrentFloorNotifier

Strategy (eager loading pattern, no race conditions):
1. At startup, eagerly load ALL beacon content (MAC -> floorId map) into memory
2. On each BLE scan, synchronously vote: which floorId appears most in confirmed beacons?
3. The floor with most votes = current floor
4. SHORTCUT: If only 1 floor exists in Firestore -> auto-select immediately (no vote needed)

### 5.4 Floor Plan Rendering
File: screens/indoor/indoor_screen.dart -> _FloorMapView

CRITICAL: Image + painter are both positioned with EXACT computed bounds (not Positioned.fill).
Without this, painter coordinates don't align with the image because BoxFit.contain
creates letterboxing that the painter doesn't know about.

Math:
  if (containerAspect < imgAspect) {
    imgRenderW = containerW;
    imgRenderH = containerW / imgAspect;
  } else {
    imgRenderH = containerH;
    imgRenderW = containerH * imgAspect;
  }
  offsetX = (containerW - imgRenderW) / 2;  // centre horizontally
  // Both Image.network AND CustomPaint use same Positioned(left:offsetX, top:0, width:imgRenderW, height:imgRenderH)

Beacon pixel -> screen:
  screenX = (pixelX / imageWidthPixels) * imgRenderW
  screenY = (pixelY / imageHeightPixels) * imgRenderH

### 5.5 Content / Data Layer
File: services/content_service.dart

Pattern: SQLite-first, Firestore fallback.
- getBeaconsForFloor(floorId): fetches ALL beacons, filters by floorId in Dart
  (DO NOT use Firestore .where('floorId',...) - unreliable if some docs missing field)

### 5.6 SQLite Schema (v5)
File: services/database_service.dart

  CREATE TABLE floors (
    id TEXT PRIMARY KEY, display_name TEXT, floor_number INTEGER,
    image_url TEXT, image_width_px REAL, image_height_px REAL
  );

  CREATE TABLE beacon_content (
    mac_address TEXT PRIMARY KEY, object_name TEXT, description TEXT,
    image_url TEXT, floor_id TEXT, pixel_x REAL, pixel_y REAL, ...
  );

v5 dropped and recreated tables to add floor_id, pixel_x, pixel_y columns.

---

## 6. Critical Constants (lib/app/constants.dart)

  proximityTriggerMetres    = 4.0   (Max distance to show exhibit)
  beaconConfirmationThreshold = 3   (Consecutive hits required before triggering)
  beaconTimeoutSeconds      = 8     (Remove if not seen within this time)
  knownBeaconUuids          = [...]  (UUIDs to filter YOUR beacons from others)
  knownMacPrefix            = '0E:A5:26:34:00:'
  beaconTxPower             = -59   (dBm at 1m, calibrate per device)
  kalmanQ / kalmanR                 (Kalman noise params)

---

## 7. Current State

### Working
- Outdoor GPS mode: place detection + AI narration
- BLE scanning: 14 beacons detected and confirmed
- Floor detection: single floor auto-selected immediately
- Beacon markers on map: positioned correctly at pixel coordinates
- All beacon names loading on map overlay
- Beacon list: shows nearby exhibits with distance + profile pictures
- Floor selector tabs: shown when multiple floors exist
- AppBar refresh button: force-refetches floor data from Firestore

### Current Blocking Issue
Floor plan image is NOT loading (HTTP 404).

Root cause: Floor plan file was deleted or not properly uploaded to Firebase Storage.
Fix (must be done in Firebase Console):
  1. Upload floor plan PNG to Firebase Storage -> floors/ folder
  2. Copy the HTTPS download URL (has ?alt=media&token=...)
  3. Paste into imageUrl of the floors Firestore document
  4. Tap the Refresh button (top-right of Indoor screen AppBar)

### Non-blocking Warnings (ignore)
- withOpacity deprecated in indoor_map_painter.dart, home_screen.dart
- Unused import in outdoor_screen.dart
- Variable naming in ekf_filter.dart

---

## 8. Coordinate System for Beacon Placement

- Floor plan image: 1280 x 1707 pixels
- To get pixelX/pixelY: open the PNG in MS Paint, hover over room center,
  read coordinates from the bottom status bar
- Store in Firestore as pixelX (number), pixelY (number)
- Origin: top-left of image = (0, 0)

---

## 9. Refresh Button

AppBar has a refresh icon. When tapped:
  1. ContentService.refreshFloorConfigs() -> force-fetches floors from Firestore
  2. ref.invalidate(floorsProvider) + ref.invalidate(floorBeaconsProvider)
  3. currentFloorProvider.notifier.refreshFloors() -> re-detects floor
  4. Shows SnackBar "Floor plan refreshed"

Use whenever imageUrl or floor data is updated in Firestore.

---

## 10. Gemini Integration

File: services/gemini_service.dart
Model: gemini-1.5-flash

- Indoor exhibits: 20-100 words base mode (scales with available info)
- Outdoor places: slightly longer (more public info available)
- Deep dive: expands with internet-grounded content
- If no data: says "I don't have much info about this" — NEVER hallucinates

---

## 11. Remaining Work

1. Floor plan image loading (pending user Firebase Storage upload — NOT a code issue)
2. BLE-triggered auto-play TTS (when user walks within 4m, auto-start narration)
3. Pulsing animation on beacon markers (currently static diamonds)
4. Multi-floor expansion (architecture ready, just add floors Firestore documents)
5. Fix deprecated withOpacity calls (cosmetic, non-breaking)

---

## 12. Absolute Rules — DO NOT Violate

1. NEVER use orderBy on Firestore floors collection (no composite index exists). Sort client-side.
2. ALWAYS use Image.network for floor plans (NOT CachedNetworkImage — caches errors stale).
3. getBeaconsForFloor MUST filter in Dart (NOT Firestore .where query — unreliable).
4. Beacon MAC lookup MUST use .toUpperCase() consistently everywhere.
5. FloorConfig.imageWidthPixels and imageHeightPixels MUST match actual PNG dimensions.
6. CurrentFloorNotifier._init() MUST use eager loading (pre-load all data, no async in BLE callbacks).
7. Do NOT remove ekf_filter.dart, madgwick_filter.dart, pdr_engine.dart — they are referenced.
