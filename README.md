# Autonomous Tour Guide 🏛️

A next-generation, location-aware tour guide application built with Flutter, Firebase, and the Groq LLM API. The app seamlessly transitions between outdoor (GPS-based) and indoor (BLE Beacon-based) navigation to provide an uninterrupted and highly interactive museum experience.

## Features ✨

*   **Hybrid Location Tracking:** Smoothly transitions between Outdoor (GPS via Geolocator/Google Maps) and Indoor (BLE Beacons) modes using an advanced Sensor Fusion engine.
*   **Multi-Floor Indoor Navigation:** Uses RSSI-weighted scoring to accurately determine the user's floor inside a venue without flickering.
*   **AI Tour Guide (Deep Dive):** Powered by Groq's Llama-3 models. Offers "Quick Info" for fast summaries and "Deep Dive" interactive chats where users can ask conversational questions about exhibits.
*   **Offline Resilience:** Caches Firestore data (beacons, floor plans, exhibit metadata) in a local SQLite database, allowing basic functionality even when the network drops.
*   **Dynamic Floor Plans:** Renders custom vector floor plans on the fly using a robust path-drawing algorithm.

## Architecture 🏗️

The project utilizes a modern Flutter stack:
*   **State Management:** Riverpod (`flutter_riverpod`)
*   **Routing:** GoRouter
*   **Backend / DB:** Firebase Firestore (remote) + sqflite (local cache)
*   **AI Integration:** Groq REST API
*   **Proximity:** flutter_blue_plus (for BLE iBeacons)
*   **Maps:** google_maps_flutter

## Getting Started 🚀

Follow these instructions to run the project locally.

### 1. Prerequisites
*   Flutter SDK (v3.24+)
*   Android Studio / Xcode
*   A [Firebase](https://firebase.google.com/) account
*   A [Groq](https://console.groq.com/) API Key

### 2. Environment Setup

To keep your API keys secure, this project uses `flutter_dotenv`. 

1. Create a file named `.env` in the root directory (alongside `pubspec.yaml`).
2. Add your Groq API key:

```env
GROQ_API_KEY=your_actual_api_key_here
```

### 3. Firebase Configuration

Due to security reasons, the Firebase configuration files are intentionally omitted from this repository. You must connect your own Firebase project:

1. Install the Firebase CLI: `npm install -g firebase-tools`
2. Log in: `firebase login`
3. Run the FlutterFire CLI from the root of this project:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```
4. This will generate `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`.

### 4. Run the App

Install dependencies and run:

```bash
flutter pub get
flutter run
```

*Note: BLE Beacon scanning requires a physical device. It will not work on iOS/Android simulators.*

## Database Structure 🗄️

If you are setting up your own Firebase, the app expects the following collections:

*   **`floors`**: Floor plan data (dimensions, path strings).
*   **`beacons`**: Beacon metadata (MAC address, uuid, objectName, description, imageUrl, videoUrl).
*   **`places`**: Places content (title, description, imageUrl, videoUrl, related items).

## License 📄
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
