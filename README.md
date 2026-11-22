# Pocko • 🍡
> **Log in 3 seconds offline. Match slips privately. Settle trips with zero awkward math.**  
> *The Flagship Cross-Platform Travel Expense & Smart Bill Splitter powered by Genuine Firebase AI Logic Hybrid Inference.*

> ## 🌐 Try Live Web App: **[https://pocko-hybrid-ai.web.app](https://pocko-hybrid-ai.web.app)**
> Open it in Chrome on a phone, tablet or desktop. No sign-up: tap **Try Tokyo Demo Trip** on the landing page and you are inside a synced group trip in seconds.

[![Live Web App](https://img.shields.io/badge/Live%20Web%20App-pocko--hybrid--ai.web.app-10B981?logo=googlechrome&logoColor=white&style=for-the-badge)](https://pocko-hybrid-ai.web.app)

[![Firebase AI Logic](https://img.shields.io/badge/Firebase%20AI%20Logic-Hybrid%20Inference-FFCA28?logo=firebase&logoColor=black)](#runtime-firebase-ai-logic-verification-for-hackathon-judges)
[![Flutter 3.x](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Platforms](https://img.shields.io/badge/Platforms-Web%20%7C%20Android%20%7C%20iOS%20%2F%20iPadOS-10B981)](#target-platforms)
[![Tests Passing](https://img.shields.io/badge/Tests-673%2F673%20Passed%20(100%25)-10B981?logo=checkmarx)](#testing--verification)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Hackathon](https://img.shields.io/badge/%23BuildHybridAI-2026%20Global%20Entry-6366F1)](#)

---

## 🧭 Table of Contents
1. [Elevator Pitch & Target Platforms](#-elevator-pitch--target-platforms)
2. [The Problem & Value Proposition](#-the-problem--value-proposition)
3. [Why Hybrid AI? (On-Device vs. Cloud)](#-why-hybrid-ai-on-device-vs-cloud-architecture)
4. [Runtime Firebase AI Logic Verification (For Judges)](#-runtime-firebase-ai-logic-verification-for-hackathon-judges)
5. [System Architecture](#-system-architecture)
6. [Complete Tech Stack](#-complete-tech-stack)
7. [Testing & Quality Verification](#-testing--verification)
8. [Getting Started & Local Setup](#-getting-started--local-setup)
9. [Detailed Specifications & Devpost Guide](#-deep-dive-blueprint--devpost-guide)

---

## 🌟 Elevator Pitch & Target Platforms

Traveling with friends should create lasting memories—not endless spreadsheets, crumpled receipts, or awkward Venmo requests. **Pocko** is an offline-first travel expense tracker and automated debt simplifier engineered with a **genuine hybrid AI inference runtime**. 

Whether you are deep inside the Tokyo subway with zero cell service, hiking in the Swiss Alps, or splitting a street food banquet in Bangkok, Pocko processes natural voice dictation and typed multi-expense notes **locally on-device in under 100 milliseconds** at zero cloud cost. When complex foreign receipts, currency conversion insights, or multi-line slip photos are captured, Pocko smoothly orchestrates cloud fallback to **Gemini 3.1 Flash Lite → Gemini 3.8 Flash** via Firebase AI Logic.

### The 3 Hybrid AI Pillars
1. **Privacy-First On-Device PII Shield:** card and account digits are masked on the device before any AI sees a slip; only the last four ever sync, and slips never leave the phone.
2. **Neuro-Symbolic Deterministic Expense Engine + Audit Trail:** the LLM only extracts words; prices, multipliers, splits and totals are computed and checked in code, and every expense keeps the original prompt as an audit trail.
3. **One Flutter Codebase Bridging 3 Native Hybrid AI Runtimes:** Chrome's built-in Gemini Nano (web), Android AICore Gemini Nano and Apple Foundation Models (iOS / iPadOS), all behind one Firebase AI Logic `PREFER_ON_DEVICE` policy, with Cloud Gemini (`gemini-3.1-flash-lite`, then `gemini-3.8-flash`) as the only fallback (there is no regex stand-in: if neither answers you get an honest error and Try again).

**App Check:** reCAPTCHA Enterprise (web) • Play Integrity (Android) • Apple DeviceCheck (iOS / iPadOS); debug providers only on developer builds and `localhost`.

### Target Platforms
| Platform | Target Hardware / Environment | Hybrid AI Engine | Bridge Mechanism |
|---|---|---|---|
| 🌐 **Web** | Chrome Desktop & Chromium Browsers | Chrome Built-in AI (W3C Prompt API) + Gemini 3.1 Flash Lite → Gemini 3.8 Flash | `dart:js_interop` + [`web/firebase_ai_web.js`](web/firebase_ai_web.js) |
| 🤖 **Android** | Samsung Galaxy S26+ & Pixel 9+ (Android 14+) | Gemini Nano via Android AICore / ML Kit + Gemini 3.1 Flash Lite → Gemini 3.8 Flash | `MethodChannel` + [`HybridAiPlugin.kt`](android/app/src/main/kotlin/com/hybridtrip/ai/travmate/HybridAiPlugin.kt) |
| 🍏 **iOS / iPadOS** | iPad Air M4 & iPhone 16+ (iPadOS 26+ / iOS 18+) | Apple Foundation Models on-device + Gemini 3.1 Flash Lite → Gemini 3.8 Flash | `MethodChannel` + [`HybridAiPlugin.swift`](ios/Runner/HybridAiPlugin.swift) |

---

## 💔 The Problem & Value Proposition

### The Problem
* **Friction Kills Logging:** Travelers postpone logging expenses because opening rigid spreadsheet forms, picking 8 dropdown fields, and calculating splits manually while walking is frustrating. By the end of the trip, days of spending are lost.
* **Network Blackouts:** Remote destinations, subways, flights, and foreign roaming dead zones break traditional cloud-only expense apps.
* **The "Receipt Pileup" Nightmare:** One person pays hotel deposits, another pays bullet trains, and everyone has bank notifications and paper receipts with private account numbers. Matching who paid what is stressful.
* **Awkward Web of Debts:** In a 4-person trip, settling debts often results in a convoluted web of 6–10 repetitive peer-to-peer transfers with foreign exchange conversion confusion.

### The Pocko Solution
1. **3-Second "Light Intelligence" Capture:** Tap the glowing center `+`: the live page stays full-bleed at 1.0x under a clean ~92% dark scrim that fades in across the whole screen (**no blur**, no shrink, no black border, so it stays buttery) while a giant 240 px Pocko zooms in. Speak (it waits **3.5 s of dead air** before auto-confirming) or type naturally (*"Ramen 1 thousand with Alex, Maya and Liam, taxi 2.5k for me"*): spoken multipliers (`thousand`, `thousan`, `k`, `million`, `m`...) become numbers, every mentioned member is picked up, and one **Confirm** starts the analysis while your words shimmer. The sentence returns with tappable item, price **and member-name** highlights; the category pill sits on its own row under it, a live mini expense card previews exactly how the entry will look, and the name-only member pills stay in two-way sync with the highlighted names. A second **Confirm** saves. A subtle **Manual Expense** action opens the standard Add Expense sheet, where Pocko suggests a category after 2.5 s of idle typing.
2. **100% Offline-First Architecture:** On-device local LLM execution paired with Cloud Firestore offline persistence ensures zero downtime anywhere in the world.
3. **Smart Slip Matcher (Privacy Shield, "Grade Pocko's work"):** Upload a slip photo or run a curated sample. Card numbers, IBANs, e-mails and holder names are masked on-device *before* any model sees them; plain bank notifications stay on 🟢 local AI while itemized foreign receipts use the ☁️ cloud fallback. Slips never sync to your group. Every logged expense sits side by side with its candidate slip: tap **✓ Correct** or **✕ Wrong** (pick a different slip, add one, or choose *Paid in Cash (No Slip Needed)*). Each card carries a compact telemetry footer such as `🟢 (Local) • 92ms`, `☁️ (Cloud) • 640ms` or `(Sim) • 48ms`.
4. **Greedy Debt Simplification (O(N log N)):** Automatically reduces multi-party webs of debt to a maximum of N - 1 optimal transfers with 1-click settlement.

---

## ⚡ Why Hybrid AI? (On-Device vs. Cloud Architecture)

Pocko implements the official **`PREFER_ON_DEVICE`** hybrid paradigm. It doesn't treat on-device AI as an afterthought or a novelty mock—it is the default primary execution engine.

| Attribute | 🟢 On-Device Inference (`PREFER_ON_DEVICE`) | ☁️ Cloud Fallback (`IN_CLOUD`) |
|---|---|---|
| **Primary Engine** | **Gemini Nano 4** (AICore) / **Apple Foundation Models** / **Chrome Prompt API** | **Gemini 3.1 Flash Lite → Gemini 3.8 Flash** via Firebase AI Logic |
| **Typical Latency** | **45ms – 110ms** (Instant, zero network roundtrip) | **650ms – 1,400ms** (Network dependent) |
| **Connectivity** | **100% Offline** (Airplanes, subways, remote trails) | Requires active Internet connection |
| **Privacy & Security** | Data never leaves device RAM; local PII/account masking | Processed via enterprise Google Cloud security |
| **API / Compute Cost** | **\$0.00** (Zero marginal cost for millions of inputs) | Standard low-cost Gemini Flash token pricing |
| **Primary Tasks** | Natural language expense parsing, multi-item splitting, category tagging | Complex multi-line foreign receipts, currency conversion insights, older devices |
| **Token Limits** | Prompt < 4,000 tokens; output capped at 256 to 512 tokens | Large context multimodal reasoning |

---

## 🔍 Runtime Firebase AI Logic Verification (For Hackathon Judges)

Judges inspecting this repository can verify that **official Firebase AI Logic SDKs are genuinely imported and executed at runtime** (there is **no regex fallback**: when no real model can answer, Pocko says so instead of guessing):

### 1. Web Hybrid AI (`dart:js_interop` + Firebase JS SDK 12.5.0)
* **[`web/firebase_ai_web.js`](web/firebase_ai_web.js)**:
  - Imports from the official Firebase JS SDK **12.5.0+** (the first release with hybrid on-device inference):
    ```javascript
    import { getAI, getGenerativeModel, GoogleAIBackend, InferenceMode } from "https://www.gstatic.com/firebasejs/12.5.0/firebase-ai.js";
    const model = getGenerativeModel(ai, {
      mode: InferenceMode.PREFER_ON_DEVICE,          // value: 'prefer_on_device' (lowercase)
      inCloudParams: { model: "gemini-3.1-flash-lite", generationConfig: { responseMimeType: "application/json" } },
    });
    ```
  - Reads the real executed location from `result.response.inferenceSource` (`on_device` / `in_cloud`).
  - If no Firebase project is configured (`window.firebaseConfig`) or the SDK call fails, it calls Chrome's **W3C Prompt API** (`LanguageModel`, Chrome 139+) directly for genuine on-device Gemini Nano. The deprecated `window.ai` is never used.
  - `checkModelStatus()` reports honest availability (`LanguageModel.availability()`), which powers the sandbox runtime probe.
  - Automatically enables `self.FIREBASE_APPCHECK_DEBUG_TOKEN = true` on `localhost`.
  - Uses its own named Firebase app (`pocko-ai-bridge`) with App Check initialized, because this module loads a separate copy of the JS SDK from FlutterFire's. Without it Firebase AI Logic answers `401 App Check token is invalid` when enforcement is on. A distinct app name also avoids the "reCAPTCHA has already been rendered" clash on production builds.
  - Sets `thinkingConfig: { thinkingBudget: 0 }` for the cloud model: expense parsing needs no reasoning, and thinking models otherwise burn the 512-token budget and return truncated JSON (retried once without the setting if a model rejects it).
  - The default cloud model is `gemini-3.1-flash-lite` (measured **1-2 s**; Remote Config key `cloud_fallback_model` can override it without a release). The bridge tries one 12 s attempt per model and then falls back to `gemini-3.8-flash`, which was measured at 5-14 s with occasional hangs past 25 s. Older IDs such as `gemini-2.5-flash` return `404 ... no longer available to new users`; `gemini-flash-lite-latest` rejects `thinkingBudget` with a generic 400, which the bridge retries without it.
* **[`lib/services/hybrid_ai/web_hybrid_ai_bridge_web.dart`](lib/services/hybrid_ai/web_hybrid_ai_bridge_web.dart)**:
  - Modern Dart 3 interop calling `window.firebaseAiWeb.generateContent(...)` (prompt, lowercase mode, Remote Config model/token budget, optional receipt image) across `@JS()` bindings.
* **[`lib/services/hybrid_ai/web_hybrid_ai_bridge.dart`](lib/services/hybrid_ai/web_hybrid_ai_bridge.dart)**:
  - Conditional export routing to `web_hybrid_ai_bridge_web.dart` on Web and `web_hybrid_ai_bridge_stub.dart` on VM to keep `flutter test` 100% green.

### 2. Android Native Hybrid Bridge (`MethodChannel` + Firebase BoM 34.10.0)
* **[`android/app/build.gradle.kts`](android/app/build.gradle.kts)**:
  - Declares official Firebase AI Logic & On-Device dependencies:
    ```kotlin
    implementation("com.google.firebase:firebase-ai:18.2.0")
    implementation("com.google.firebase:firebase-ai-ondevice:16.0.0-beta08") // minSdk 26
    ```
* **[`android/app/src/main/kotlin/com/hybridtrip/ai/travmate/HybridAiPlugin.kt`](android/app/src/main/kotlin/com/hybridtrip/ai/travmate/HybridAiPlugin.kt)**:
  - Calls `Firebase.ai(backend = GenerativeBackend.googleAI()).generativeModel(modelName, generationConfig, onDeviceConfig = OnDeviceConfig(mode = InferenceMode.PREFER_ON_DEVICE))` and reads `response.inferenceSource` for truthful telemetry.
  - **Model fallback chain:** requested model first (with Gemini Nano via AICore when the mode allows, 12 s), then `gemini-3.1-flash-lite`, then `gemini-3.8-flash`, cloud-only with one 12 s attempt each; a model that rejects `thinkingConfig` is retried once without it.
  - Cloud fallback is **`gemini-3.1-flash-lite`** with thinking disabled (`thinkingConfig { thinkingBudget = 0 }`): expense parsing needs no reasoning, and thinking models would otherwise burn the 512-token budget and return truncated JSON.
  - Decodes base64 receipt images into a `Bitmap` (single-image on-device input, multimodal in the cloud).
  - **Never fabricates results**: if Firebase is not configured or the call fails it replies `AI_UNAVAILABLE` and Dart shows an honest banner (offline vs. timeout vs. rejected, with the reason) and a **Try again** that re-sends the same words or recording.
  - Returns `{ "rawJson", "inferenceSource": "on_device" | "in_cloud", "latencyMs", "modelInfo" }`.
  - *Verified:* `flutter build apk --debug` compiles this plugin (the APK's dex contains the `gemini-3.1-flash-lite` default and the `thinkingBudget` call). Not yet run on a physical Android device.

### 3. iOS / iPadOS Native Hybrid Bridge (`MethodChannel` + Apple Foundation Models + FirebaseAILogic 13.x)
* **[`ios/Runner/HybridAiPlugin.swift`](ios/Runner/HybridAiPlugin.swift)**:
  - **On-device:** Apple's own Foundation Models framework (`SystemLanguageModel.default` + `LanguageModelSession`, iOS 26+ with Apple Intelligence). It is weakly linked behind `#available(iOS 26.0, *)`, so the app still launches on iOS 15-25.
  - **Cloud fallback:** the stable Firebase `GenerativeModel` API (`FirebaseAILogic`, firebase-ios-sdk **13.1.1**, linked directly into the Runner target through Swift Package Manager) with `GenerationConfig(thinkingConfig: ThinkingConfig(thinkingBudget: 0))`, `gemini-3.1-flash-lite` first, then `gemini-3.8-flash`, one 12 s attempt each (a model that rejects `thinkingConfig` is retried once without it). Receipt photos are decoded to a `UIImage` and always use the cloud model (Apple on-device is text-only).
  - Routing follows the Remote Config mode (`ONLY_ON_DEVICE`, `ONLY_IN_CLOUD`, `PREFER_IN_CLOUD`, default `PREFER_ON_DEVICE`). firebase-ios-sdk 13.0 *removed* the interim `HybridModel` / `GenerativeModelSession` / `SystemLanguageModel` types, so hybrid routing lives in the plugin itself.
  - Replies **exactly once** per call; when no runtime is available it returns `AI_UNAVAILABLE` instead of simulated data.
  - *Verified:* `flutter build ios --debug --no-codesign` (Xcode 27) compiles this file with `FirebaseAILogic` and `FoundationModels` linked. Not yet run on a physical iPad.

### 4. Firebase Cloud Services Integration
* **Cloud Firestore Real-Time Group Sync ([`lib/services/sync/squad_sync_service.dart`](lib/services/sync/squad_sync_service.dart))**:
  - Live synchronization keyed by a per-install random 6-digit Group Code under `trips/{squadCode}`. Echo-free (writer ids), deletions propagate, joiners get their own identity (kept until the cloud copy lists them), a freshly created group always listens to its own code, and bank slips never leave the device.
  - Enabled with offline persistence: `FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true)`.
* **Firebase Anonymous Authentication ([`lib/main.dart`](lib/main.dart))**:
  - Frictionless anonymous device authentication (`signInAnonymously()`) on app launch.
* **Firebase App Check ([`lib/main.dart`](lib/main.dart))**:
  - Initialized with `AndroidDebugProvider` / `AppleDebugProvider` for developer builds (Play Integrity / DeviceCheck otherwise) and, on the web, **reCAPTCHA Enterprise (Fraud Defense)** on production hosts (`*.web.app`, `*.firebaseapp.com`); the debug token is only ever used on `localhost` / `127.0.0.1` ([`lib/services/firebase/app_check_config.dart`](lib/services/firebase/app_check_config.dart), mirrored in [`web/firebase_ai_web.js`](web/firebase_ai_web.js)).
* **Firebase Remote Config ([`lib/services/remote_config/remote_config_service.dart`](lib/services/remote_config/remote_config_service.dart))**:
  - Dynamically fetches runtime AI policy parameters: `ai_inference_mode`, `cloud_fallback_model`, `max_output_tokens`, and `prompt_template_override`. **They are applied to every request** (mode in any casing, model name, clamped token budget, `{{userInput}}`-style prompt templates) with safe fallbacks for blank values.
  - Live diagnostics card with manual "Fetch & Activate" exposed in [`HybridSandboxScreen`](lib/features/sandbox/hybrid_sandbox_screen.dart).

---

## 🧑‍⚖️ Judge Quick Tour (2 minutes, no microphone needed)

0. **Open the live app: [https://pocko-hybrid-ai.web.app](https://pocko-hybrid-ai.web.app)** (or run it yourself with `flutter run -d chrome`). The app opens on an animated **landing story** of three illustrated scenes (log live at a café offline in 3 s, a bank slip snapping onto its waiting expense, and the on-device privacy shield masking `•••• 4829`). Tap **Try Tokyo Demo Trip** for pre-loaded data in one click, or **Skip / Next ➔ Set up my trip** to create your own trip (name, destination that auto-pairs the currency, home currency, friends as name tags: *no app install needed for friends*). **Manage Group ➔ New Trip / Setup Wizard** reopens it any time.
1. Tap the glowing **+**. Type something like *Dinner 1 thousand yen, Alex paid, split with Maya and Liam* (or tap the mic: online it records ONE continuous clip and sends it to Gemini audio; a 5 s thinking pause never cuts it) and press **Confirm**. Pocko juggles while your words shimmer, then returns your sentence with glowing item, price and category pills and a telemetry pill: `🟢 On-Device AI • Gemini Nano` or `☁️ Cloud Gemini • gemini-3.1-flash-lite • 1.8 s`. Tapping a pill once selects that expense (no keyboard); tapping it again, or the pencil, edits it. If no real model can answer (for example offline on a phone without Gemini Nano) a red banner explains why and offers Try again; Pocko never guesses with a regex.
2. Tap any pill to edit it instantly (item name or price). Tapping an item also focuses it: the friend avatars and the **paid by** chip below follow the focused item. Press **Confirm** again: a short **Logged** beat, then the overlay fades back to the live page. Home, Expenses and Settle all update at once (and **Undo** is one tap away).
3. Open **Matcher**. Grade Pocko's pairs with **✓ Correct** / **✕ Wrong** (the Wrong sheet offers other slips, a gallery pick, sample slips or *Paid in Cash*), or run **Sample Slips**: *Card alert • TeamLab* (local AI, PII masked, exact match) and *Paris bistro receipt (EUR)* (itemized cloud fallback, converted to ¥). Cards end with `🟢 (Local) • 71ms` / `☁️ (Cloud) • 640ms` style footers; the pending-slip count lives on the Matcher icon in the navigation bar.
4. On **Expenses**, scrub the date strip (*All Dates*, *Pre-Trip*, each trip day) to see that day's total. On **Settle**, read each directional transfer lane (debtor ➔ amount ➔ creditor), expand *Why this amount?* to see exactly which expenses make it up, then press **Record Payment** (or **+ Record Repayment** for any money that changed hands, optionally with a slip photo): balances and charts recalculate immediately and the payment appears in **Repayment History** (**Undo** is one tap away).
5. Tap the terminal icon for the **Diagnostic Sandbox**: it probes the *real* runtime (Chrome Prompt API / Firebase / native bridge), shows live Remote Config values and lets you force each inference mode.

---

## 🏗️ System Architecture

```mermaid
flowchart TD
    subgraph UI[Pocko Presentation Layer • Material 3 Expressive]
        Shell[PockoMainShell<br/>5-Item Translucent Navigation Bar (no blur)]
        Home[Tab 0: TripHomeScreen<br/>Trip Summary, Group Net Balance, Top 3 Expenses, Recent]
        Expenses[Tab 1: ExpensesCanvasScreen<br/>Date Filter Strip (All / Pre-Trip / each day), Category Chips, Timeline Feed]
        Capture[Center '+': AiExpenseCaptureSheet<br/>Light Intelligence Overlay • Inline Highlighted Transcript]
        Matcher[Tab 3: SmartSlipMatcherScreen<br/>Grade Pocko's Work (✓ / ✕ / Cash), PII Masking, Telemetry Footer]
        Settle[Tab 4: VisualSettleScreen<br/>Donut, Transfer Lanes, Itemized Breakdown, Record Repayment + History]
        Squad[SquadSetupScreen Modal<br/>6-Digit Group Code, Members, New Trip Wizard]
        Landing[OnboardingGate<br/>Animated Story & First-Trip Setup]
        Sandbox[HybridSandboxScreen<br/>Raw Telemetry & Remote Config Diagnostics]
    end

    subgraph State[Riverpod State Management]
        TripCtrl[TripController<br/>NotifierProvider&lt;TripController, TripState&gt;]
        RCSvc[RemoteConfigNotifier<br/>NotifierProvider&lt;RemoteConfigNotifier, RemoteConfigData&gt;]
    end

    subgraph Logic[Domain Logic & Hybrid Orchestration]
        DebtSimp[DebtSimplifier<br/>O N log N Greedy Net Balance Algorithm]
        HybridAi[HybridAiService<br/>Remote Config Policy, Real AI or an Honest Error]
        SlipPipe[SlipAnalyzer<br/>PiiMasker ➔ Hybrid AI ➔ SlipMatcher]
        PromptBuilder[ExpensePromptBuilder<br/>Compact &lt;200-Word Single-Turn Schema]
        SyncSvc[SquadSyncService<br/>Firestore Offline Persistence & Sync]
    end

    subgraph Bridges[Cross-Platform Hybrid AI Bridges]
        direction TB
        AndroidBridge[Android AICore Bridge<br/>com.google.firebase:firebase-ai<br/>OnDeviceConfig PREFER_ON_DEVICE]
        AppleBridge[Apple Foundation Models Bridge<br/>FirebaseAI preferOnDevice<br/>iOS 18+ / iPadOS 26+]
        WebBridge[Chrome Web Interop Bridge<br/>dart:js_interop + firebase/ai<br/>InferenceMode.PREFER_ON_DEVICE]
    end

    subgraph Cloud[Firebase Cloud Infrastructure]
        Firestore[(Cloud Firestore<br/>Offline Cache + Real-Time Snapshot Listener)]
        RemoteConfig[(Firebase Remote Config<br/>Dynamic Runtime AI Policies)]
        Auth[Firebase Anonymous Auth<br/>Frictionless Secure Device UID]
        AppCheck[Firebase App Check<br/>reCAPTCHA Enterprise & Debug Providers]
    end

    Home --> TripCtrl
    Expenses --> TripCtrl
    Matcher --> TripCtrl
    Settle --> TripCtrl
    Squad --> TripCtrl
    Landing --> TripCtrl
    Capture --> HybridAi
    Matcher --> SlipPipe
    SlipPipe --> HybridAi
    Sandbox --> HybridAi
    Sandbox --> RCSvc

    TripCtrl --> DebtSimp
    TripCtrl --> SyncSvc
    HybridAi --> PromptBuilder

    HybridAi -->|MethodChannel| AndroidBridge
    HybridAi -->|MethodChannel| AppleBridge
    HybridAi -->|dart:js_interop| WebBridge

    SyncSvc <-->|trips/{squadCode}| Firestore
    RCSvc <--> RemoteConfig
    TripCtrl -.-> Auth
    WebBridge -.-> AppCheck
```

---

## 🛠️ Complete Tech Stack

| Layer | Technology | Package / Artifact | Purpose |
|---|---|---|---|
| **Frontend Framework** | Flutter 3.x / Dart 3.x | `flutter` | Cross-platform UI for Web, Android, and iOS |
| **State Management** | Riverpod 3.x | `flutter_riverpod: ^3.5.0` | Reactive unidirectional state architecture |
| **Design System** | Google Material 3 Expressive | `google_fonts: ^6.2.1` | `Plus Jakarta Sans` typography, custom colors, pill radii |
| **Motion & Micro-interactions** | Flutter Animate | `flutter_animate: ^4.5.2` | Floating bobs, aura pulses, and confetti particles |
| **Custom Mascot** | Flutter CustomPainter | `lib/core/widgets/pocko_mascot.dart` | 6 animated vector moods (waving, listening, juggling, scanning, celebrating, sleepy) with blinking, gaze drift and microphone-reactive expressions |
| **Charts & Visualizations** | FL Chart | `fl_chart: ^1.3.1` | Interactive settlement donut chart & balance indicators |
| **Speech-to-Text** | Speech To Text | `speech_to_text: ^7.0.0` | Ambient live voice transcription with live sound-level feedback and a demo-dictation fallback |
| **Image Capture** | Image Picker | `image_picker: ^1.1.2` | Receipt photo and gallery slip capture |
| **Android AI Logic** | Firebase AI Logic | `com.google.firebase:firebase-ai:18.2.0` + `firebase-ai-ondevice` | Native Android Gemini Nano & Gemini Flash hybrid bridge |
| **iOS AI Logic** | Firebase iOS SDK | `FirebaseAILogic (v12.13+, SPM)` | Native Apple Foundation Models & Gemini Flash hybrid bridge |
| **Web AI Logic** | Firebase JS SDK | `firebase/ai (v12.5+)` | Hybrid mode + W3C Prompt API / Gemini Nano on Chrome Desktop (139+) |
| **Cloud Database** | Cloud Firestore | `cloud_firestore: ^7.1.0` | Real-time multi-device sync with offline persistence |
| **Cloud Auth** | Firebase Auth | `firebase_auth: ^7.0.1` | Anonymous device authentication |
| **Security & Verification** | Firebase App Check | `firebase_app_check: ^0.5.1` | Token attestation & reCAPTCHA Enterprise (Fraud Defense) protection |
| **Dynamic Configuration** | Firebase Remote Config | `firebase_remote_config: ^7.0.1` | Remote AI policy overrides without app updates |
| **Automated Testing** | Flutter Test | `flutter_test` | 46 test suites (673 tests) covering logic, services, widgets, layouts |

---

## 🧪 Testing & Verification

Pocko maintains a **100% pass rate across 46 test suites (673 unit, service and widget tests)**:

```bash
flutter analyze   # No issues found!
flutter test      # 00:08 +673: All tests passed!
flutter build web --no-tree-shake-icons   # ✓ Built build/web
```

| Suite | What it proves |
|---|---|
| `debt_simplifier_test`, `trip_controller_test` | Greedy settlement math, mixed-currency conversion, settlement payments that recalculate balances, undo/restore, member guards, group-code handling, date filters (incl. Pre-Trip), top expenses, cash slips, re-linking slips |
| `hybrid_ai_service_test`, `expense_prompt_builder_test` | English parsing (multi-expense, payers, splits, currencies), Remote Config policy, prompt templates, receipts |
| `slip_pipeline_test` | PII masking, match tiers, local-vs-cloud routing for the four sample slips |
| `squad_sync_service_test` | Firestore (de)serialization, malformed documents, offline behaviour |
| `*_screen_test`, `pocko_main_shell_test` | Reactive UI across Home (Top Expenses, nav badge, no banners) / Expenses (date strip, `showCheckmark: false`, time metadata) / Matcher (✓ Correct, ✕ Wrong, Paid in Cash, telemetry footer) / Settle (transfer lanes, itemized breakdown, Record Repayment, Repayment History) / Group / Sandbox, sliding nav indicator, **capture overlay dim & drop (no `BackdropFilter`, ~92% scrim, 0.965 page scale)**, Manual Expense to Add Expense sheet, swipe-to-delete + Undo, empty states |
| `pocko_bottom_sheet_and_footer_test`, `settle_graph_and_breakdown_test`, `transcript_tokens_test` | Global `showPockoBottomSheet` (80 % max height, drag handle, keyboard inset, no stray `showModalBottomSheet`), pair breakdown math, transcript tokenizer behind the inline pills |
| `ai_expense_capture_sheet_test` | No preset chips, **Confirm** with `Icons.check_rounded` (no emoji), **Manual Expense**, 240 px hero + zoom, moving-gradient `ShaderMask`, analyzing shimmer/wave, always-visible member bar with **auto-selection** rules, inline pill editing + validation, focus switching, Logged + Undo, **320×568 phones, keyboard insets, iPad/desktop widths** |
| `live_inference_gate_test` | Fast path: negative/timed-out probe returns at once, cached probes, call ceiling, no surfaced errors |
| `spoken_numbers_and_members_test` | `1 thousand` / `1 thousan` / `one thousand` / `2.5k` / `15 thousand` / `1 million` / `1m`, typos, multi-member lists (`Alex, Maya and Liam`, `&`, `everyone`, `all`), prompt rules and digit normalization |
| `capture_precision_polish_test` | 3.5 s voice pause, name-only member pills, 58 px Confirm / Back, **bi-directional transcript <-> pill sync**, category row, live mini preview card, Pocko 24 px selector menus, spoken multipliers in the flow |
| `badge_manual_assist_test` | Manual Expense 2.5 s auto-category debounce (lock, restart, edit mode), Matcher badge on the icon corner (phone and rail) |
| `onboarding_test` | Animated story (swipe, dots, Skip), setup card (destination pairs currency, friend tags, validation), Start Trip / Try Tokyo Demo Trip, gate transition, Manage Group wizard, 320 px and tablet layouts |
| `smart_pricing_and_splits_test` | Neuro-symbolic maths (`each`, `per person`, `apiece`, `per head`, quantity, `%` surcharge, discounts ignored, head-counts ignored), `ParsedExpenseDraft` totals / breakdown labels / legacy + new schema, `with` vs `for`, `everyone`, third-party payers, spoken numbers, currency slang (`bucks`, `quid`...), compound utterances, normalizer repairs (self-multiplied totals, invented percentages), prompt schema |
| `travel_category_gazetteer_test` | Disneyland, Universal Studio, Teamlab, Cosmo Land, Lego land, museums and the National Center are never `MISC`; venue-vs-item override (`Disneyland headband` = Souvenirs, `Universal churros` = Meals); brands (Suica, Ichiran, 7-Eleven, Don Quijote, APA...); country / car-park false positives; Manual Expense and post-LLM `MISC` rescue; prompt anchors |
| `raw_prompt_and_per_person_ui_test` | `500 yen each` = ¥1,500 then ¥1,000 / ¥2,000 as member pills toggle, badge text, hand-typed price detaches, committed totals, `Expense.note` holds the verbatim prompt (also for multi-item utterances), the edit sheet shows and preserves it, italic one-line preview on Expense cards |
| `real_ai_only_test` | **No regex fallback**: a real service with no runtime throws `AiUnavailableException` (offline vs. timeout vs. rejected), the red banner with Try again, Clear and the banner pinned above the fold, 2-step tap (select, then edit), spaced thousands (`2 200` = 2200), self-corrections, `plus 10 percent`, dictation hints |
| `real_ai_hardening_test` | `"Eat Ramen with Maya and Liam for 8 thousand yen"` always gives title `Ramen`, ¥8,000, `MEAL`, split `You, Maya, Liam` (offline parser **and** the `ExpenseNormalizer` that repairs real model answers: member-name titles, leading verbs, dropped multipliers); `gemini-3.8-flash` + thinking off verified in the Kotlin, Swift, JS and Dart sources (no `gemini-2.5-flash` left); Manual Expense asks `HybridAiService.suggestCategory` after the 2.5 s pause |
| `selector_and_toast_test` | `PockoSelector` popovers capped at 320 px, scrolling, instant search above 5 options (filter, "No matches", clear); `showPockoToast` pill card (icon, message, detail, shrinking bar, Undo), guaranteed 5 s auto-dismiss with an action button, replacement; `(3) Liam, Maya, Alex` formatting with ellipsis |
| `capture_nine_point_test` | Typing 0 -> 1 -> N characters never drops focus or re-creates the `TextField`; member-name pills share the title/price pill size, weight, padding and radius; explicit selected names; the celebratory **Logged** beat (burst, confetti, spring pill, 950 ms); mascot sizes 96-112 px (headers) and 140-160 px (empty states) incl. 320 px phones; the 3 illustrated landing scenes |
| `group_sync_listener_test` | Live group sync wiring with an in-memory Firestore stand-in: a trip created right after the app starts listens to its own code (not the starting code), the wizard keeps listening, and a joiner stays in the member list until the cloud copy contains them |
| `itemized_split_test` | **Unequal dish splits**: `"Sushiro dinner, I paid: mine 1200, Maya salmon 1800, Liam udon 950"` is ONE `¥3,950` expense with `customSplits`, never three; ordinary sentences stay un-itemized; the normalizer collapses a model that split the bill and drops invented shares; name → member-id mapping; `shareFractions` sum to 1; net balances, transfer plan, pair breakdown and repayments follow each person's own dish; photo size guard for the 1 MiB Firestore limit |
| `permissions_and_repayment_test` | **Host vs guest**: the creator device is the host; guests cannot edit / delete the host's entries (polite message) but can edit their own; Lock Guest Edits; host-only member removal and reset; legacy trips stay open; swipe / tap blocking and the 👑 Host badge + lock switch in Manage Group; `recordRepayment` validation, live deduction from net balances and creator-only undo |
| `editor_redesign_and_perf_test` | Redesigned expense sheet (currency pill inside Amount, themed date / time pickers, searchable Category + Paid By selectors, Equal Split vs Custom Amounts with live total and validation), Receipt / Slip photo (camera + gallery via an injectable picker, preview, full screen, remove, permission errors), landing footer hidden while the keyboard is open, country flags in the destination picker, hidden tabs run no tickers |
| `gemini_audio_capture_test` | **Gemini voice pipeline**: `transcript` + `items` parsing (blank transcript is `null`, fenced JSON, normalizer repairs keep the transcript), the audio prompt, `SilenceDetector` (3.5 s of dead air only after speech, adaptive threshold), WAV header for Web, one uninterrupted recording with no restarts, long mid-sentence pauses, Stop, too-short clips, offline / denied-permission fallback to `speech_to_text`, the verbatim transcript saved as the Original Voice Prompt, plus Kotlin / Swift / JS / permission wiring and `en_US` + dictation mode |
| `voice_dictation_test` | **Continuous voice dictation**: `DictationBuffer` appends Android / iOS segments (`"Eat ramen with Maya"` + pause + `"mine 1200 Maya 1800 yen"` keeps every word), never duplicates Web cumulative transcripts, whole-word prefix guard, manual edit / Clear sync; a scripted `SpeechEngine` proves the automatic listen restart after a segment ends, the 3.5 s dead-air timer (reset only by new words, not by echoes), Stop analyzes at once, `no_match` restarts while permission errors stop, the Clear chip |
| `sync_field_level_test` | **Concurrency-safe sync**: only changed entries are written (`expenseMap.<id>`, `memberMap.<id>.name`...), a join / rename / new expense from three devices all survive, a restarted device only adds (never deletes or overwrites), schema 2 round trip, key-order-proof comparison, legacy documents |
| `members_and_session_test` | **Renaming keeps every bill intact** (ids never change, balances / splits / repayments identical, validation, host vs guest), the AI and offline parser see the new names on every capture, **Join Group** with a chosen name (unique names, invite links, not-found, from a placeholder), local session restore and `has_seen_landing` |
| `placeholder_landing_test` | **First-launch-only landing** (Get Started / Join Group / Demo / Skip), replay from Settings without wiping storage, placeholder Home (fresh install and upcoming-only trip), **null-trip crash guards** (`+`, Add Expense, Receipt Scan), Settings and rename UI, the AI source badge, iPad 11" portrait and landscape |
| `walkthrough_regressions_test` | Findings of the final real-user walkthrough: negative amounts print `-¥6,800`, the Expenses strip total follows the category filter, the setup card keeps focus after adding a friend, the **repayment typo guard** (a second tap for an amount above what is owed), separate *edit* / *delete* denial messages, the gallery button label scales instead of truncating |
| `telemetry_and_mascot_test`, `pocko_mascot_test` | Telemetry pill variants, all six mascot moods animating, blink schedule |

Widget tests inject a deterministic stand-in for the model (`hybridAiServiceProvider` override, test-only); the shipped app never uses it. `real_ai_only_test` proves a real service with no runtime throws `AiUnavailableException` instead of regex-parsing.

## 🚢 Release builds for demo recording

Profile and release builds open straight from the home screen (debug builds on iOS 14+ only run while attached to Flutter / Xcode). They normally use the production App Check providers, which need Play Integrity / DeviceCheck set up in Firebase. For developer devices keep the **debug provider** with `--dart-define=APP_CHECK_DEBUG=true` and register the printed debug token once (Firebase console → App Check → Apps → Manage debug tokens). The token is kept as long as the app's data is not cleared; use **Settings → Replay Landing Page** to repeat the intro for a take without wiping anything.

```bash
# Android (APK for a phone: sideload with adb)
flutter build apk --release --dart-define=APP_CHECK_DEBUG=true
adb install -r build/app/outputs/flutter-apk/app-release.apk

# iOS / iPadOS (signed with your team; the device needs Developer Mode on and the developer profile trusted)
flutter build ios --release --dart-define=APP_CHECK_DEBUG=true
xcrun devicectl device install app --device <device-id> build/ios/iphoneos/Runner.app
```

Store builds omit the flag and use the production providers.

## 🚀 Getting Started & Local Setup

### 1. Prerequisites
- [Flutter SDK 3.x](https://flutter.dev/docs/get-started/install) (`^3.13.0`)
- [Node.js & npm](https://nodejs.org) (for Firebase CLI)
- Google Chrome (Desktop)

### 2. Clone & Install Dependencies
```bash
git clone https://github.com/henpokpok/Pocko.git && cd Pocko
flutter pub get
```

### 3. Enabling On-Device AI by Platform

#### 🌐 Enabling Gemini Nano in Google Chrome (Desktop)
1. Open Chrome 139+ on desktop (Canary also works).
2. Navigate to `chrome://flags/#prompt-api-for-gemini-nano` ➔ Set to **Enabled**.
3. Navigate to `chrome://flags/#optimization-guide-on-device-model` ➔ Set to **Enabled BypassPrefRequirement**.
4. Restart Chrome and visit `chrome://components` ➔ Find **Optimization Guide On Device Model** ➔ Click **Check for update** until downloaded.

#### 🤖 Enabling Android AICore (Samsung Galaxy S26+ / Pixel 9)
1. Ensure device runs Android 14+ with latest Google Play Services.
2. In Settings ➔ Developer Options, verify **AICore Persistent Service** is running.
3. Native builds link directly to `com.google.firebase:firebase-ai-ondevice` (minSdk 26).

#### 🍏 Enabling iOS 18+ / iPadOS 26+ (iPad Air M4)
1. In iPad Settings ➔ Apple Intelligence & Siri, verify on-device foundation models are active.
2. Add the `FirebaseAILogic` product (firebase-ios-sdk 13.1.1+) via Swift Package Manager; the Swift bridge compiles with `#if canImport(FirebaseAILogic)` and otherwise reports `AI_UNAVAILABLE` so Dart can use its labelled simulation.

### 4. (Optional) Link Your Firebase Project for Web

Without any config, Chrome's built-in Gemini Nano still runs on-device. To enable the ☁️ cloud fallback and live Remote Config on the web build, add before the module script in `web/index.html`:
```html
<script>window.firebaseConfig = { apiKey: "...", projectId: "...", appId: "..." };</script>
```
For Android/iOS run `flutterfire configure` (adds `google-services.json` / `GoogleService-Info.plist`).

### 5. Running the App
```bash
# Run on Chrome Web (Default)
flutter run -d chrome

# Run on connected Android device
flutter run -d android

# Run on connected iOS / iPad device
flutter run -d ios
```

### 6. Building for Production / Firebase Hosting
```bash
# Build Web release bundle (Wasm & JS interop ready)
flutter build web --no-tree-shake-icons
# (optional) override the reCAPTCHA Enterprise key ID: --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=your_key_id

# Deploy to Firebase Hosting
firebase deploy --only hosting
```

---

## 📖 Deep-Dive Blueprint & Devpost Guide

For complete engineering specifications, vector mascot anatomy, prompt schema benchmarks, and our official Devpost hackathon submission narrative, refer to:

👉 **[`docs/PROJECT_BLUEPRINT.md`](docs/PROJECT_BLUEPRINT.md)**

---

## 📄 License
This project is licensed under the [Apache License 2.0](LICENSE).  
Developed for the **#BuildHybridAI 2026** Global Hackathon.
