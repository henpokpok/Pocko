// web/firebase_ai_web.js
// Firebase AI Logic Hybrid Inference Web Module for Pocko (#BuildHybridAI 2026)
//
// Strategy (all three layers are real runtimes, never mocks):
//   1. Firebase AI Logic JS SDK (>= 12.5.0) with
//        getGenerativeModel(ai, { mode: InferenceMode.PREFER_ON_DEVICE, inCloudParams })
//      which delegates to Chrome's built-in Gemini Nano (W3C Prompt API) first and
//      falls back to Gemini Flash in the cloud.
//   2. If the Firebase project is not configured (no `window.firebaseConfig`) or the SDK call
//      fails, call Chrome's W3C Prompt API (`LanguageModel`) directly for on-device inference.
//   3. If neither is available the promise rejects and the Dart side switches to its clearly
//      labelled offline simulation.
//
// Provide your project config before this module loads, e.g. in web/index.html:
//   <script>window.firebaseConfig = { apiKey: "...", projectId: "...", appId: "..." };</script>

import { initializeApp, getApp } from "https://www.gstatic.com/firebasejs/12.5.0/firebase-app.js";
import {
  initializeAppCheck,
  ReCaptchaV3Provider,
} from "https://www.gstatic.com/firebasejs/12.5.0/firebase-app-check.js";
import {
  getAI,
  getGenerativeModel,
  GoogleAIBackend,
  InferenceMode,
} from "https://www.gstatic.com/firebasejs/12.5.0/firebase-ai.js";

// Enable App Check debug token in localhost / developer mode per official Firebase guidelines
if (typeof window !== "undefined") {
  if (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1") {
    self.FIREBASE_APPCHECK_DEBUG_TOKEN = true;
    console.log("[Firebase AppCheck] Debug token enabled (localhost). Safelist token in Firebase Console.");
  }
}

// reCAPTCHA v3 site key used for App Check on production web builds. It must match the key passed to
// Flutter as --dart-define=RECAPTCHA_V3_SITE_KEY. Override it before this module loads with
//   <script>window.firebaseAppCheckSiteKey = "your-site-key";</script>
// (On localhost the debug token above is used instead and the key is never exchanged.)
const DEFAULT_RECAPTCHA_V3_SITE_KEY = "6LeIxAcTAAAAAJcZVRqyHh71UMIEGNQ_MXjiZKhI";

// Chrome's built-in Prompt API requires explicit languages (English only for Pocko).
const PROMPT_API_IO = {
  expectedInputs: [{ type: "text", languages: ["en"] }],
  expectedOutputs: [{ type: "text", languages: ["en"] }],
};

/** Lower-case values are what the Firebase JS SDK uses: InferenceMode.PREFER_ON_DEVICE === "prefer_on_device". */
function resolveMode(raw) {
  const m = String(raw || "").toLowerCase().replace(/-/g, "_");
  if (m.includes("only_on_device") || m.includes("onlyondevice")) {
    return InferenceMode.ONLY_ON_DEVICE;
  }
  if (m.includes("only_in_cloud") || m.includes("onlyincloud")) {
    return InferenceMode.ONLY_IN_CLOUD;
  }
  return InferenceMode.PREFER_ON_DEVICE;
}

/** Placeholder values such as "..." or "YOUR_API_KEY" must never count as a real configuration. */
function isRealValue(v) {
  if (typeof v !== "string") return false;
  const t = v.trim();
  return t.length > 3 && !/^\.+$/.test(t) && !/^(your|replace|<|todo|xxx)/i.test(t);
}

/** Synchronous, zero-cost check used by the Dart fast path. */
function hasUsableFirebaseConfig() {
  const c = window.firebaseConfig;
  return !!(c && isRealValue(c.apiKey) && isRealValue(c.projectId) && isRealValue(c.appId));
}

/** Rejects after [ms] so a stuck availability check or download can never block the UI. */
function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(label + " timed out after " + ms + "ms")), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

// Availability is cached briefly so repeated taps never pay for the check twice.
let availabilityCache = { value: null, at: 0 };
const AVAILABILITY_TTL_MS = 30000;
const AVAILABILITY_PROBE_MS = 400;

/** Returns "unavailable" | "downloadable" | "downloading" | "available" | "unsupported". */
async function promptApiAvailability() {
  const now = Date.now();
  if (availabilityCache.value && now - availabilityCache.at < AVAILABILITY_TTL_MS) {
    return availabilityCache.value;
  }
  let value;
  try {
    if (typeof self.LanguageModel === "undefined") {
      value = "unsupported";
    } else {
      value = await withTimeout(
        self.LanguageModel.availability(PROMPT_API_IO),
        AVAILABILITY_PROBE_MS,
        "LanguageModel.availability",
      );
    }
  } catch (e) {
    value = "unsupported";
  }
  availabilityCache = { value, at: now };
  return value;
}

async function promptApiGenerate(prompt, maxTokens) {
  // Only a model that is already on disk is used on the interactive path. A model that still has to
  // be downloaded would block the tap for minutes, so Dart falls back to its labelled local parser.
  const status = await promptApiAvailability();
  if (status !== "available") {
    throw new Error("Chrome Prompt API not ready (" + status + ")");
  }
  const session = await withTimeout(
    self.LanguageModel.create({
      ...PROMPT_API_IO,
      initialPrompts: [
        {
          role: "system",
          content: "You are a strict JSON generator for a travel expense app. Reply with JSON only.",
        },
      ],
    }),
    4000,
    "LanguageModel.create",
  );
  try {
    const text = await withTimeout(session.prompt(prompt), 8000, "LanguageModel.prompt");
    return text.length > maxTokens * 8 ? text.slice(0, maxTokens * 8) : text;
  } finally {
    if (session.destroy) session.destroy();
  }
}

/**
 * This module loads its own copy of the Firebase JS SDK, separate from the one FlutterFire uses, so
 * the app created here has no App Check of its own. Without it Firebase AI Logic rejects the call
 * with 401 "App Check token is invalid" when enforcement is on. Initialize it once per app.
 */
const BRIDGE_APP_NAME = "pocko-ai-bridge";

/**
 * A dedicated, named app for this module. FlutterFire registers the "[DEFAULT]" app with its own copy
 * of the SDK; two App Check instances on the same app name would fight over one reCAPTCHA container
 * ("reCAPTCHA has already been rendered in this element"). The debug token is stored per origin, so
 * the token registered for the Flutter app also covers this one.
 */
function getBridgeApp() {
  try {
    return getApp(BRIDGE_APP_NAME);
  } catch (_) {
    return initializeApp(window.firebaseConfig, BRIDGE_APP_NAME);
  }
}

const appCheckReady = new WeakSet();
function ensureAppCheck(app) {
  if (appCheckReady.has(app)) return;
  appCheckReady.add(app);
  try {
    initializeAppCheck(app, {
      provider: new ReCaptchaV3Provider(window.firebaseAppCheckSiteKey || DEFAULT_RECAPTCHA_V3_SITE_KEY),
      isTokenAutoRefreshEnabled: true,
    });
  } catch (e) {
    // Already initialized for this app (or App Check unavailable): the AI call still goes ahead.
    console.warn("[Firebase AI Web] App Check init skipped:", e && e.message ? e.message : e);
  }
}

let firebaseModelCache = null;
let firebaseModelKey = "";

// Fast, reliable default for structured extraction (measured 1-2 s). The slower
// gemini-3.8-flash stays available as the fallback and via Remote Config.
const FAST_CLOUD_MODEL = "gemini-3.1-flash-lite";
const SLOW_CLOUD_MODEL = "gemini-3.8-flash";

// One attempt must answer within this long, otherwise the next model in the chain is
// tried: a hung request used to burn the whole 20 s ceiling before falling back.
const CLOUD_ATTEMPT_TIMEOUT_MS = 8000;

// Spoken-expense audio (inline data) is uploaded and transcribed in one call: a little more room.
const AUDIO_ATTEMPT_TIMEOUT_MS = 15000;

// Expense parsing needs no reasoning. Thinking models (Gemini 2.5+/3.x) otherwise spend
// the small output budget on hidden thinking tokens, which truncates the JSON mid-object
// and adds seconds. Some models (e.g. gemini-flash-lite-latest) reject thinkingConfig
// with a generic 400 "invalid argument": those are remembered here and retried without it.
const modelsRejectingThinking = new Set();

function rejectsThinkingConfig(err) {
  const msg = String((err && err.message) || err);
  return /thinking/i.test(msg) || (/\[400/.test(msg) && /invalid argument/i.test(msg));
}

function getFirebaseModel(mode, cloudModel, maxTokens) {
  const key = [mode, cloudModel, maxTokens, !modelsRejectingThinking.has(cloudModel)].join("|");
  if (firebaseModelCache && firebaseModelKey === key) return firebaseModelCache;
  const app = getBridgeApp();
  ensureAppCheck(app);
  const ai = getAI(app, { backend: new GoogleAIBackend() });
  firebaseModelCache = getGenerativeModel(ai, {
    mode,
    inCloudParams: {
      model: cloudModel,
      generationConfig: {
        responseMimeType: "application/json",
        maxOutputTokens: maxTokens,
        ...(modelsRejectingThinking.has(cloudModel)
          ? {}
          : { thinkingConfig: { thinkingBudget: 0 } }),
      },
    },
    onDeviceParams: { createOptions: PROMPT_API_IO },
  });
  firebaseModelKey = key;
  return firebaseModelCache;
}

/**
 * Expose window.firebaseAiWeb interface for the Dart js_interop bridge
 */
window.firebaseAiWeb = {
  /**
   * Synchronous snapshot for the Dart fast path (no awaits, no network):
   * { firebaseConfigured, promptApiPresent }.
   */
  quickStatus: function () {
    return {
      firebaseConfigured: hasUsableFirebaseConfig(),
      promptApiPresent: typeof self.LanguageModel !== "undefined",
    };
  },

  /** True only when the on-device model is already downloaded (400ms probe, cached 30s). */
  isOnDeviceReady: async function () {
    return (await promptApiAvailability()) === "available";
  },

  isAvailable: async function () {
    return hasUsableFirebaseConfig() || (await promptApiAvailability()) !== "unsupported";
  },

  /** Honest diagnostics: reports what this browser can really run. */
  checkModelStatus: async function () {
    const prompt = await promptApiAvailability();
    const configured = hasUsableFirebaseConfig();
    const onDeviceReady = prompt === "available";
    let status;
    let modelInfo;
    if (onDeviceReady) {
      status = configured ? "READY_ON_DEVICE_AND_CLOUD" : "READY_ON_DEVICE";
      modelInfo = configured
        ? "Gemini Nano (Chrome Prompt API) + Firebase AI Logic cloud fallback"
        : "Gemini Nano (Chrome Prompt API). Add window.firebaseConfig to enable cloud fallback";
    } else if (prompt === "downloadable" || prompt === "downloading") {
      status = "MODEL_" + prompt.toUpperCase();
      modelInfo = "Gemini Nano is " + prompt + " (Chrome 139+). First prompt will trigger the download";
    } else if (configured) {
      status = "CLOUD_ONLY";
      modelInfo = "Firebase AI Logic cloud (on-device model unavailable: " + prompt + ")";
    } else {
      status = "UNAVAILABLE";
      modelInfo = "No on-device model (" + prompt + ") and no Firebase config. Simulated engine will be used";
    }
    return {
      isAvailable: onDeviceReady || configured,
      status,
      modelInfo,
      runtime: onDeviceReady ? "prompt_api" : configured ? "firebase_cloud" : "none",
    };
  },

  /**
   * Executes real hybrid inference. Options:
   *   { prompt, mode, cloudFallbackModel, maxOutputTokens, receiptBase64, audioBase64, mimeType }
   * `audioBase64` (+ `mimeType`, e.g. audio/wav) sends the recorded voice as inline data to the
   * cloud model, which returns the verbatim transcript together with the parsed items.
   * Resolves { rawJson, inferenceSource: "on_device" | "in_cloud", latencyMs, modelInfo }.
   */
  generateContent: async function (options) {
    const startTime = performance.now();
    const prompt = (options && options.prompt) || "";
    const cloudModel = (options && options.cloudFallbackModel) || FAST_CLOUD_MODEL;
    const maxTokens = (options && options.maxOutputTokens) || 512;
    const audioBase64 = options && options.audioBase64;
    // Audio and receipt photos are both multimodal inline data: cloud model only.
    const receiptBase64 = (options && options.receiptBase64) || audioBase64;
    const mode = audioBase64 ? InferenceMode.ONLY_IN_CLOUD : resolveMode(options && options.mode);
    const mimeType = (options && options.mimeType) || (audioBase64 ? "audio/wav" : "image/jpeg");
    const attemptTimeout = audioBase64 ? AUDIO_ATTEMPT_TIMEOUT_MS : CLOUD_ATTEMPT_TIMEOUT_MS;
    const elapsed = () => Math.round(performance.now() - startTime);

    // ---- 1. Firebase AI Logic hybrid SDK ------------------------------------------------
    if (hasUsableFirebaseConfig()) {
      try {
        // Receipt photos are multimodal: route through the cloud model.
        const request = receiptBase64
          ? [prompt, { inlineData: { data: receiptBase64, mimeType } }]
          : prompt;
        // Model chain: the requested model first, then the other fast/slow model, so a
        // hung or retired model never costs more than one short attempt.
        const chain = [cloudModel];
        for (const m of [FAST_CLOUD_MODEL, SLOW_CLOUD_MODEL]) if (!chain.includes(m)) chain.push(m);

        const attempt = (model) =>
          withTimeout(
            getFirebaseModel(mode, model, maxTokens).generateContent(request),
            attemptTimeout,
            "Firebase AI Logic (" + model + ")",
          );

        let result;
        let usedModel = cloudModel;
        let lastErr;
        for (const model of chain) {
          try {
            try {
              result = await attempt(model);
            } catch (firstErr) {
              // The model rejected thinkingConfig: retry the same model once without it.
              if (modelsRejectingThinking.has(model) || !rejectsThinkingConfig(firstErr)) throw firstErr;
              modelsRejectingThinking.add(model);
              result = await attempt(model);
            }
            usedModel = model;
            break;
          } catch (err) {
            lastErr = err;
            console.warn("[Firebase AI Web] " + model + " failed, trying next model:", err && err.message ? err.message : err);
          }
        }
        if (!result) throw lastErr;
        const response = result.response;
        const rawJson = response.text();
        // SDK >= 12.5.0 reports "on_device" | "in_cloud" (lower-case) on response.inferenceSource.
        const reported = String(response.inferenceSource || "in_cloud").toLowerCase();
        const source = reported.includes("device") ? "on_device" : "in_cloud";
        return {
          rawJson,
          inferenceSource: source,
          latencyMs: elapsed(),
          modelInfo:
            source === "on_device"
              ? "Gemini Nano (Chrome Built-in AI via Firebase AI Logic)"
              : usedModel + " (Firebase AI Logic Cloud)",
        };
      } catch (fbErr) {
        console.warn("[Firebase AI Web] Hybrid SDK call failed; trying Chrome Prompt API:", fbErr);
        if (mode === InferenceMode.ONLY_IN_CLOUD || receiptBase64) throw fbErr;
      }
    }

    // ---- 2. Direct Chrome Prompt API (W3C LanguageModel) ---------------------------------
    if (mode !== InferenceMode.ONLY_IN_CLOUD && !receiptBase64) {
      const rawJson = await promptApiGenerate(prompt, maxTokens);
      return {
        rawJson,
        inferenceSource: "on_device",
        latencyMs: elapsed(),
        modelInfo: "Gemini Nano (Chrome Prompt API, on-device)",
      };
    }

    // ---- 3. Nothing reachable: let Dart fall back to its labelled simulation -------------
    throw new Error("No hybrid AI runtime reachable (configure window.firebaseConfig or enable Chrome Prompt API)");
  },
};
