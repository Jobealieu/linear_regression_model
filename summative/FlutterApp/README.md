# ENTROPY mobile app

One-page Flutter app that sends a remittance service profile to the ENTROPY API
(`POST https://entropy-remit-api.onrender.com/predict`) and shows the predicted all-in cost.

## Run it

Requires the Flutter SDK (3.32 or newer) and an Android emulator or phone.

```bash
cd summative/FlutterApp
flutter pub get
flutter emulators --launch <emulator id>   # list ids with: flutter emulators
flutter run
```

Press **fill sample** to load a valid quote (USA to Gambia, online, mobile wallet), then **Predict**.
The API runs on Render's free tier, so the first request after a quiet spell can take up to a minute.

## Code

| File | What it does |
|---|---|
| `lib/api.dart` | Calls the API (`/predict` and `/`) and turns validation errors into readable sentences |
| `lib/predict_page.dart` | The page: 10 labelled text fields, the Predict button, the model panel |
| `lib/output_panel.dart` | The display area for the prediction or the error message |
| `lib/theme.dart` | Colours and font (JetBrains Mono, SIL Open Font License, `assets/fonts/OFL.txt`) |

```bash
flutter analyze   # strict analyzer settings
flutter test      # API client and page tests, no network needed
```
