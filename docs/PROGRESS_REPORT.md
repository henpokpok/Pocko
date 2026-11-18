# Pocko progress report

**Project:** Pocko (`travmate`), a hybrid-AI group-expense app for #BuildHybridAI 2026
**Stack:** Flutter 3.47 / Dart ^3.13 / Riverpod 3, Firebase (Auth, Firestore, App Check, Remote Config, AI Logic)
**Bundle ID:** `com.hybridtrip.ai.travmate` · **Firebase project:** `pocko-hybrid-ai`
**Report date:** 2026-11-18

This report follows the work from the first real Firebase setup, through installing on a Galaxy S22+ and an iPad Air (M4), to the voice-capture problems and where things stand now. Each phase lists what was wrong, what was done, and how it was checked. Things not yet verified are called out.

---

## 1. Where we are now

| Area | Status |
|---|---|
| `flutter analyze` | 0 issues |
| `flutter test` | **606 / 606 pass** (41 suites) |
| `flutter build web --no-tree-shake-icons` | clean |
| `flutter build apk --debug` | clean |
| `flutter build ios --debug --no-codesign` | clean |
| Galaxy S22+ (`RFCT5032EVV`) | debug APK installed; real-device capture and Gemini audio verified earlier |
| iPad Air 11-inch (M4) | release build installed, opens from the home screen; voice capture + Gemini confirmed working by the user |
| Cloud AI | `gemini-3.1-flash-lite` first, `gemini-3.8-flash` as fallback, through Firebase AI Logic on Web, Android and iOS |

Test count over time: 431 → 486 → 503 → 540 → 541 → 545 → 606.

---

## 2. Timeline

### Phase 1. Firebase setup and live group sync
- Ran `flutterfire configure`, enabled App Check, anonymous auth and Firestore.
- Tested joining a group from a second device and found **two live-sync bugs**:
  1. a subscription created in a microtask kept listening to the starting group code instead of the new trip's own code;
  2. a joiner could be dropped from the member list by the first (stale) snapshot.
  Both were fixed and covered by `group_sync_listener_test` (in-memory Firestore stand-in).
- Cleaned up temporary test documents under `trips/`. **Incident:** one Firestore document that was not a test document (code `546-236`) was deleted by mistake. It was disclosed at the time; nothing else was affected.

### Phase 2. Real Firebase AI Logic on the web
Problems found and fixed while calling the real service:
| Symptom | Cause | Fix |
|---|---|---|
| 401 from the AI call | the bridge app had no App Check | named app `pocko-ai-bridge` plus `initializeAppCheck` |
| reCAPTCHA "already rendered" | two apps used the same container | distinct app name |
| 404 on the model | model retired | moved to the current model |
| Truncated JSON | thinking tokens used the output budget | thinking budget 0, with a per-model retry if a model rejects `thinkingConfig` |

App Check debug tokens are **per origin**, so the web test origin needed its own registered token.

### Phase 3. UX polish and AI intelligence
- **9-point UX/UI polish:** searchable selectors, typing keeps focus, equal member-pill sizes, names summary, "Logged" celebration, mascot sizes, toast with a 5 s timer, three illustrated landing scenes.
- **Neuro-symbolic pricing:** the model returns intent (`unitAmount`, `amountMode`, `quantity`, `extraPercent`) and Dart computes the total; an `ExpenseNormalizer` cross-checks every real model answer against the deterministic offline parser.
- **Travel gazetteer** so Disneyland, teamLab, Cosmo Land and similar names are never `MISC`.
- **Raw prompt audit trail** saved in `Expense.note`.
- **Latency investigation:** a 16.6 s cloud spike was traced to a slow model; the default became `gemini-3.1-flash-lite` (about 1-2 s) with the slower model as fallback and 8 s per attempt.

### Phase 4. Native Android and iOS builds
- **Android:** Kotlin plugin with a model fallback chain and `withTimeout`.
- **iOS:** the firebase-ios-sdk 13.x removed `HybridModel`, `GenerativeModelSession` and `SystemLanguageModel`, so `HybridAiPlugin.swift` was rewritten (Apple Foundation Models on-device, stable Firebase `GenerativeModel` cloud). The Xcode project was edited to compile the plugin and link `FirebaseAILogic`.
- Both `flutter build apk --debug` and `flutter build ios --debug --no-codesign` were made clean.

### Phase 5. First install on the Galaxy S22+
- Installed with `adb` to `RFCT5032EVV`.
- Android App Check needed its own **debug token**, read from the phone's logcat and registered in the Firebase console.
- Real-device capture verified end to end: **Cloud route, 2548 ms**.

### Phase 6. Six-point real-device upgrade (from Galaxy testing)
1. **Performance:** each tab wrapped in `RepaintBoundary` + `TickerMode`; the landing footer hides while the keyboard is open.
2. **Country flags** in the destination picker (plus Taiwan and Hong Kong currencies).
3. **Unequal splits:** `Expense.customSplits`; settlement math, pair breakdown and repayments follow each person's own dish; one itemized bill is ONE expense with an "Itemized split" badge.
4. **Expense sheet redesign:** currency pill inside Amount, themed date/time pickers, searchable Category and Paid By, Equal Split vs Custom Amounts, Original Voice/Text Prompt box, Receipt/Slip photo (camera + gallery).
5. **Settle screen:** directional transfer lanes, "+ Record Repayment" with an optional slip photo, Repayment History, the old graph and "How to pay" removed.
6. **Permissions:** the creating device is the Host; guests edit or delete only their own entries; "Lock Guest Edits"; "👑 Host" badge. Repayments are stored in `TripState.settlements` (extended `SettlementPayment`) rather than a separate `Trip.repayments` list.
- Photos are downscaled and compressed, and left out of the cloud copy only if a trip document would exceed Firestore's 1 MiB limit.

### Phase 7. The voice-capture bug (words wiped after a pause)
- **Symptom (Galaxy):** speak, pause, continue, and the first words disappear.
- **Cause:** Android's `SpeechRecognizer` ends a segment after about a second of quiet and then reports only the next words; assigning `recognizedWords` to the text box overwrote everything.
- **Fix:** `DictationBuffer` (committed text + live segment, Web cumulative-transcript guard), automatic listen restart while the 3.5 s dead-air timer has not fired, a Clear pill, manual-edit sync, and a `SpeechEngine` seam so multi-segment dictation could be tested without a microphone.
- **Phone logs** showed several final results arriving in one session, which matched the diagnosis, and no errors or crashes.

### Phase 8. Gemini multimodal audio, and the three follow-up fixes
Offline recognition still mis-heard words, followed the phone's non-English locale and dropped syllables across restarts. So:
- **Online path (primary):** one uninterrupted recording (`record` package; AAC `audio/mp4` on Android/iOS, WAV on Web) with a silence detector (adaptive noise floor, 3.5 s after speech started). The audio goes to Gemini as inline data on Web, Android and iOS with the trip context, and one call returns `{"transcript", "items"}`. The transcript fills the capture view and is saved as the Original Voice Prompt.
- **Offline path (fallback):** `speech_to_text` pinned to `en_US` and dictation mode; `DictationBuffer` keeps each segment's high-water mark so dips, empty partials and a missing `finalResult` never lose words.
- **Edit Expense sheet:** fixed nine-section order (Title, Amount, Date & Time, Category, Paid By, Receipt Photo, Split, Note, Original Voice Prompt) and stadium-pill buttons.
- **Capture overlay:** the 0.965 scale and rounded inset were removed, which had caused a black border; the page stays full-bleed under the 85% scrim.

### Phase 9. Problems found on the Galaxy after that
| Problem | Cause | Fix |
|---|---|---|
| The mic's expanding ring pushed other elements around | the ring was a normal `Stack` child, so the `Stack` grew with it | fixed-size orb box; the ring paints outside it with negative offsets and takes no part in layout (regression test samples the full ring cycle) |
| Audio "perfect" but no sign of live transcription | the transcript only arrives with the full analysis | a second, tiny transcription-only call runs in parallel and the words appear word by word while the analysis is still running; a fast analysis still holds the preview briefly |
- Phone logs showed the recorder working (AAC, 16 kHz, mono, 64 kbps) with no errors. Android does not log successful network calls, so latency log lines were added (`audio analysis in N ms`, `audio transcript preview in N ms`).

### Phase 10. Getting the app onto the iPad Air (M4)
This took several steps:
1. **Developer Mode was off** and its switch was hidden in Settings. After connecting to Xcode and re-trying, the switch appeared and was turned on.
2. **Provisioning profile did not include the iPad** (error `0xe8008012`). Building with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` added the device.
3. **Profile not trusted** on the iPad (Settings → General → VPN & Device Management). Trusting it allowed launch.
4. **Debug builds cannot be opened from the home screen** on iOS 14+ (Flutter tooling, an IDE or Xcode must start them). The fix is a profile or release build.
5. **App Check on a release build:** release builds normally use DeviceCheck, which needs an Apple key uploaded to Firebase. A new opt-in switch keeps the debug provider instead: `--dart-define=APP_CHECK_DEBUG=true`. Store builds without the flag are unchanged.
6. **Launch crash `Duplicate plugin key: HybridAiPlugin`:** `AppDelegate.swift` registered the Gemini bridge twice. It now registers once (a regression test checks this).
7. The iPad's App Check debug token was read from the console and registered in Firebase. The user then confirmed **voice capture and Gemini work on the iPad**.

### Phase 11. Polish for the final demo recording
A checkpoint commit and the tag `checkpoint-pre-polish` were made first. Then four workstreams:
1. **Groups and renaming.** Join Group from every entry point (Landing, empty Home, Settings, Manage Group) with a name chosen first and a code or invite link; rename at any time. Referential integrity was verified: expenses, `customSplits` and repayments hold immutable member ids, so a rename changes only the display name and every bill, balance and view updates without changing any amount (tests compare the stored JSON before and after). The AI roster is read fresh on every capture. **Sync was made concurrency-safe:** the trip document moved to schema 2 (maps keyed by id) and each device writes only the entries it changed; the earlier whole-document overwrite could erase a join or rename from another device.
2. **First-launch landing.** `has_seen_landing` (`shared_preferences`) plus a saved trip session, so later launches open straight on Home. **Settings → Replay Landing Page** resets only the flag, so demo takes never need a data wipe or a new App Check token.
3. **Placeholder Home.** No trip, or only a future trip, shows "Create a New Trip" and "Join Existing Group" (plus an Upcoming card). The `+` button, Add Expense and Receipt Scan ask for a trip first, so they never run on a missing trip or currency. The app holds one trip at a time, so "upcoming trips" means that trip.
4. **Final polish.** Info.plist permissions confirmed (camera, photo library, microphone, speech); iPad 11" portrait and landscape layouts tested for the placeholder, every tab, Manage Group, the sheets and the landing; a plain-language AI source badge on every capture (Cloud Gemini / On-Device / Offline fallback).

Release builds for Android and iOS with `--dart-define=APP_CHECK_DEBUG=true` both build cleanly (commands in the README).

**Not verified on devices yet:** the new schema-2 writes against the live Firestore project (the diff logic is unit-tested, the Firestore calls themselves are not), the first-launch / replay flow on the phone and iPad, and a real two-device concurrent edit. Existing cloud documents in the old array format are migrated by the first full write.

---

## 3. How to build and install

```bash
# Gates
flutter analyze
flutter test
flutter build web --no-tree-shake-icons
flutter build apk --debug
flutter build ios --debug --no-codesign

# Galaxy S22+
adb -s RFCT5032EVV install -r build/app/outputs/flutter-apk/app-debug.apk

# iPad (release build that opens from the home screen)
flutter build ios --release --dart-define=APP_CHECK_DEBUG=true
xcrun devicectl device install app --device <iPad device id> build/ios/iphoneos/Runner.app
```

Each device needs its own App Check debug token registered in the Firebase console (App Check → Apps → Manage debug tokens). Reinstalling after clearing app data can create a new token that must be registered again.

---

## 4. Known limits and things not yet verified
- The Galaxy S22+ has not yet been re-tested with the **live transcript preview** in everyday use beyond the first check, and no latency numbers for the audio call were captured yet.
- On the iPad, the **camera and photo-library flows**, group sync and the Settle/repayment screens were not exercised in this phase.
- The **debug-token App Check mode** is for developer devices only. A store release needs DeviceCheck / App Attest (or Play Integrity on Android) configured in Firebase.
- The audio path needs a network. Without one, or after a failed call, the app uses offline dictation (English only).
- A shorter, unrelated partial in offline dictation is treated as a new utterance, which could misfire on a rare mis-hearing.
- Firebase client config files (`google-services.json`, `GoogleService-Info.plist`, `firebase_options.dart`) are in the repository. They contain client API keys, not server secrets, but they should be restricted in Google Cloud and App Check should be enforced before a public release. No App Check debug tokens are stored in the repository.

---

## 5. Where to read more
- `README.md`: features, architecture, test table.
- `docs/PROJECT_BLUEPRINT.md`: detailed design (capture pipeline, voice pipeline, settlement math, permissions, design system).
