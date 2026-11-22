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
| `flutter test` | **673 / 673 pass** (46 suites) |
| `flutter build web --no-tree-shake-icons` | clean |
| `flutter build apk --debug` | clean |
| `flutter build ios --debug --no-codesign` | clean |
| Galaxy S22+ (`RFCT5032EVV`) | debug APK installed; real-device capture and Gemini audio verified earlier |
| iPad Air 11-inch (M4) | release build installed, opens from the home screen; voice capture + Gemini confirmed working by the user |
| Cloud AI | `gemini-3.1-flash-lite` first, `gemini-3.8-flash` as fallback, through Firebase AI Logic on Web, Android and iOS |

Test count over time: 431 → 486 → 503 → 540 → 541 → 545 → 606 → 616 → 617 → 635 → 640 → 642 → 663 → 668 → 669 → 673.

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
- **Capture overlay:** the 0.965 scale and rounded inset were removed, which had caused a black border; the page stays full-bleed under the 92% scrim.

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

### Phase 12. Final real-user walkthrough (web, real Firebase, two browser origins)
The built web app was run in the browser against the real Firebase project (App Check debug token registered for both `localhost:8790` and `127.0.0.1:8790`, as Device 1 and Device 2), stepping through all eight stages.

| Stage | Result |
|---|---|
| 1. Landing and first trip | **Pass.** Three scenes, flag dropdown (🇯🇵 Japan ¥ JPY), "Tokyo Autumn Trip" with Maya, Liam, Alex lands on Home. |
| 2. `+` AI capture | **Pass, real Gemini (no SIM).** Full-bleed backdrop (no black frame), typing never drops focus. Ramen each = ¥1,500 with a live pill toggle (¥2,000 with Alex); itemized sushi = ¥3,950 with `1200 / 1800 / 950`; Teamlab = Attractions ¥15,200; Disneyland headband = Souvenirs, Maya only. "Logged" animation and 5 s toast. |
| 3. Manual expense and edit sheet | **Pass.** "Shinkansen to Kyoto" auto-selects Transport after the pause; the nine sections are in the required order; searchable dropdowns, pill members, a receipt image attached, previewed and opened full screen. |
| 4. Home and Expenses | **Pass.** Totals, balances (checked by hand: You +¥27,850, Maya −¥11,800, Liam −¥8,750, Alex −¥7,300), top 3, category filter. There is no search box in the app, so search was not applicable. |
| 5. Slip Matcher | **Pass.** Badge 0 → 1 (green) → 0 → 1 (coral) → 0, card number masked (`•••• 5521`), ✓ verified, Paid in Cash. |
| 6. Settle | **Pass.** Lanes match the splits, no "How to pay", a partial ¥5,000 repayment drops Maya's debt to ¥6,800 and appears in Repayment History. |
| 7. Two-device sync | **Pass.** Joining with a code shows the trip on Device 2 and "Bee" on Device 1 live; Device 2's expense appears on Device 1; Device 2 is told it cannot edit / delete the Host's entry, can edit and delete its own; the Host deleted a guest's entry and Device 2 updated live. |

**Findings, all fixed with a regression test (`walkthrough_regressions_test`):**
1. **A stale web build** was missing the web plugin registrant, so `shared_preferences` (and, in older builds, the recorder and image picker) were not registered: the session store failed on web and the landing showed every time. A clean build (`rm -rf .dart_tool/flutter_build`) regenerated it. The gates now build web from a clean state.
2. A stray digit in the repayment amount recorded a ¥118,005,000 repayment (found by the walkthrough itself). Added a **typo guard**: a repayment above what is owed needs a second tap.
3. The friend name field lost focus after pressing Enter on the setup card; it now stays focused.
4. Negative amounts printed `¥-6,800`; they now print `-¥6,800`.
5. The Expenses strip total ignored the category filter; it now matches the listed cards.
6. Tapping a Host's entry as a guest said "can delete"; edit and delete now have separate messages.
7. The "Choose from Gallery" button truncated on a 430 px screen; the label now scales.

**Observations:** two of five cloud captures on the first run were slow (7 s, and one that exceeded the 20 s limit and fell back to the labelled offline parser, which produced the correct result); later calls took 1.3 to 4.3 s. The two cosmetic items found (the destination dropdown showed each flag twice, and large amounts clipped in the Net Balance row) were fixed afterwards: the row text no longer repeats the flag, and balance amounts scale to fit.

**Cleanup:** the temporary trip document created for this run (`trips/977-269`) was deleted with the Firebase CLI and the test server stopped. Trip documents belonging to the phone and iPad installs were left alone.

### Phase 13. Firebase Hosting, App Check on the web, and first-swipe smoothness
- **Hosting:** `firebase.json` serves `build/web` with a single-page rewrite; the live site is `https://pocko-hybrid-ai.web.app`. `.js`, `.html` and `.json` are served with `no-cache` so a redeploy is picked up at once (a one-hour browser cache had kept an old key alive after a deploy).
- **App Check on the web:** production hosts use reCAPTCHA Enterprise (Dart in `lib/services/firebase/app_check_config.dart` and the AI Logic bridge in `web/firebase_ai_web.js`); the debug token is only ever used on `localhost` / `127.0.0.1`. A first key from the wrong Cloud project failed with HTTP 400 on the token exchange; the key from the `pocko-hybrid-ai` project returns 200 and a live Gemini capture was confirmed on the hosted URL.
- **First-swipe smoothness (iPad Safari / Chrome):** all onboarding pages are built up front (`allowImplicitScrolling` plus a 4-page cache extent and keep-alive), each in its own `RepaintBoundary`; scene tickers run only for the settled, visible page and are paused while swiping. Backdrop blurs (side rail, bottom bar, `GlassCard`), the mascot's blurred ground shadow and the animated mic glow were replaced by plain translucent fills and pre-computed radial gradients, and the hero shadow was reduced to two layers (max blur 24). Plus Jakarta Sans weights are preloaded before the first frame with a 2.5 s timeout (`lib/core/theme/font_prewarm.dart`).

### Phase 14. Review fixes after the gallery screenshots
- The badge for the offline rule engine reads `Offline Safety Net • Rule Engine` (footer: `(Rule Engine)`); native on-device results read `On-Device AI • Gemini Nano` / `On-Device AI • Apple FM`, cloud results `Cloud Gemini • <model>`; the word SIM no longer appears anywhere in the UI. Native on-device results read `On-Device AI`.
- The capture scrim is 92% opaque and the nav bar / rail are 94% white with a hairline border (no backdrop blur) so the dashboard behind it no longer bleeds through the highlighted prompt.
- The Group Net Balance row omits the extra "+ Group Invite" orb for groups of four or more, so nothing clips at 412 px.
- Cloud models: `gemini-3.1-flash-lite`, then `gemini-3.8-flash`. A live check on the hosted site showed `gemini-2.5-flash` answers 404 ("no longer available to new users, use gemini-3.8-flash"), so it is deliberately not used. README rows that still said 2.5 Flash were corrected.
- Rebuild scope: the app shell watches only the trip name, sync status and Matcher badge; `MediaQuery.sizeOf` / `viewInsetsOf` replace `MediaQuery.of`; slip and receipt images decode at display size (`cacheWidth`).

### Phase 15. Real AI only (no regex fallback) after the Samsung voice test
- **Root causes found:** a failed or slow Gemini call silently fell back to the regex parser; after one failed audio call the sheet stayed on Android dictation for the rest of the session; the app's 20 s ceiling was shorter than the native chain (12 s on-device + 2 x 8 s cloud); a 1.5 s DNS check could call a slow network "offline"; and the cross-check dropped `10 percent` (it only knew `%`).
- **Fixes:** `parseExpenseText` / `parseExpenseAudio` now raise `AiUnavailableException` (offline, timeout, rejected, unavailable) and the capture sheet shows a pinned red banner with the reason and a **Try again** that re-sends the same recording or words. Ceilings are 40 s (text) / 55 s (audio), cloud attempts 12 s, the network probe tries twice with 3 s each, and online voice never downgrades to dictation. A recording ends after 6 s of dead air (a thinking pause never cuts it). The sandbox "force simulated" switch was removed.
- **Prompts and cross-checks:** `plus 10 percent`, spoken self-corrections (`4,200... oh wait no, 4,800`) and spaced thousands (`2 200`) are handled in the prompt, in `SpokenCorrections` / `SpokenNumbers.collapseSpacedThousands` and in `ExpenseNormalizer`; dictation passes phonetic hints (Michelle = Matcha, Ramming = Ramen, ...); offline dictation collapses `2 200` before analysis.
- **UI:** the first tap on a highlighted keyword only selects that expense (no keyboard); a second tap or the pencil edits. The transcript scrolls inside a box while Clear and the red banner stay pinned above the fold.
- **Demo data:** timestamps hang off 15:00 today, so shortly after midnight the demo no longer loses its Today group.

### Phase 16. Samsung S26 follow-ups
- The floating bottom bar now sits above the 3-button / gesture system bar (`SafeArea`), as does everything laid out below it.
- Offline voice: the default recognizer ("Speech Services by Google") has its own offline pack, separate from the Samsung keyboard's Voice input pack. On `error_language_unavailable` / `error_network` the app retries once with the on-device recognizer, then stops the mic **once** and shows a banner that opens the keyboard, whose own mic key works offline. No more flipping the mic on and off.
- Gemini Nano: `FirebaseAIOnDeviceNotAvailableException: On-device model is not available` on the S26 simply meant the model was not downloaded. Settings now has **On-device AI (Gemini Nano)** with status and a one-time Download button (`FirebaseAIOnDevice.checkStatus()` / `download()` through the Android bridge).
- **Mislabelled Nano answers:** the Firebase SDK prints its inference source as `On Device` / `In Cloud` (with a space). The Android bridge matched `ON_DEVICE`, so real Gemini Nano answers were reported as cloud. It now compares the SDK constant itself.
- The Nano download tile keeps showing progress after you tap Download (it used to flip back to the button while AICore was still starting), and shows download errors.

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
