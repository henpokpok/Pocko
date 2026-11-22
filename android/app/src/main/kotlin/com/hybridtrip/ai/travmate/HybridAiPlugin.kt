package com.hybridtrip.ai.travmate

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.SystemClock
import android.util.Base64
import com.google.firebase.Firebase
import com.google.firebase.FirebaseApp
import com.google.firebase.ai.InferenceMode
import com.google.firebase.ai.InferenceSource
import com.google.firebase.ai.OnDeviceConfig
import com.google.firebase.ai.ai
import com.google.firebase.ai.ondevice.DownloadStatus
import com.google.firebase.ai.ondevice.FirebaseAIOnDevice
import com.google.firebase.ai.ondevice.OnDeviceModelStatus
import com.google.firebase.ai.type.GenerativeBackend
import com.google.firebase.ai.type.PublicPreviewAPI
import com.google.firebase.ai.type.content
import com.google.firebase.ai.type.generationConfig
import com.google.firebase.ai.type.thinkingConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout

/**
 * HybridAiPlugin
 *
 * Flutter MethodChannel bridge for Firebase AI Logic hybrid inference on Android
 * (Gemini Nano via AICore, with Gemini Flash cloud fallback).
 *
 * Contract with Dart (`lib/services/hybrid_ai/hybrid_ai_service.dart`):
 * - `checkModelStatus` -> { isAvailable, status, modelInfo }
 * - `parseExpenseText` -> { rawJson, inferenceSource: "on_device" | "in_cloud", latencyMs, modelInfo }
 *
 * This bridge NEVER fabricates a result. When Firebase is not configured or the SDK call
 * fails it replies with the error code `AI_UNAVAILABLE`, and Dart switches to its clearly
 * labelled (`isSimulated`) offline engine, so telemetry shown in the UI is always truthful.
 *
 * Requires Firebase AI Logic SDK 17.10.0+ (see app/build.gradle.kts) and a configured
 * Firebase project (google-services.json) at runtime.
 */
class HybridAiPlugin : FlutterPlugin, MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.hybridtrip.ai/inference"
        const val CLOUD_FALLBACK_MODEL = "gemini-3.1-flash-lite"

        /** Slower model kept as the fallback (measured 5-14 s, occasionally hangs). */
        const val SLOW_CLOUD_MODEL = "gemini-3.8-flash"

        /** One attempt per cloud model: a hung model never costs more than this. */
        const val CLOUD_ATTEMPT_TIMEOUT_MS = 12_000L

        /** Recorded speech (inline audio) is uploaded and transcribed in one cloud call. */
        const val AUDIO_ATTEMPT_TIMEOUT_MS = 15_000L

        /** The first attempt may include Gemini Nano (AICore) cold start, so it gets longer. */
        const val ON_DEVICE_ATTEMPT_TIMEOUT_MS = 12_000L
    }

    private lateinit var channel: MethodChannel
    private var context: Context? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        scope.cancel()
        context = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "checkModelStatus" -> handleCheckModelStatus(result)
            "parseExpenseText" -> handleParseExpenseText(call, result)
            "onDeviceStatus" -> handleOnDeviceStatus(result)
            "downloadOnDeviceModel" -> handleDownloadOnDeviceModel(result)
            else -> result.notImplemented()
        }
    }

    private fun firebaseConfigured(): Boolean {
        val ctx = context ?: return false
        return try {
            FirebaseApp.getApps(ctx).isNotEmpty()
        } catch (e: Throwable) {
            false
        }
    }

    private fun handleCheckModelStatus(result: Result) {
        val configured = firebaseConfigured()
        val supportedApi = Build.VERSION.SDK_INT >= 26 // firebase-ai-ondevice minimum API level
        val status = when {
            !configured -> "FIREBASE_NOT_CONFIGURED"
            !supportedApi -> "API_LEVEL_TOO_LOW"
            else -> "READY_FIREBASE_AI_LOGIC"
        }
        val info = when {
            !configured -> "Firebase is not configured (add google-services.json). Simulated engine will be used"
            !supportedApi -> "Android 8.0+ is required for on-device inference. Cloud fallback only"
            else -> "Firebase AI Logic hybrid (Gemini Nano via AICore, fallback $CLOUD_FALLBACK_MODEL)"
        }
        result.success(
            hashMapOf<String, Any>(
                "isAvailable" to (configured),
                "status" to status,
                "modelInfo" to info,
            )
        )
    }

    // --- Gemini Nano (AICore) model lifecycle -------------------------------------------------
    // "On-device model is not available" usually just means the model has not been downloaded yet.

    @Volatile private var downloadJob: Job? = null
    @Volatile private var downloadedBytes = 0L
    @Volatile private var totalBytes = 0L
    @Volatile private var downloadError: String? = null
    @Volatile private var downloadDone = false

    @OptIn(PublicPreviewAPI::class)
    private fun handleOnDeviceStatus(result: Result) {
        if (!firebaseConfigured()) {
            result.success(hashMapOf<String, Any>("state" to "unavailable", "error" to "Firebase is not configured"))
            return
        }
        scope.launch {
            val payload = hashMapOf<String, Any>(
                "downloadedBytes" to downloadedBytes,
                "totalBytes" to totalBytes,
            )
            downloadError?.let { payload["error"] = it }
            try {
                val status = FirebaseAIOnDevice.checkStatus()
                payload["state"] = when {
                    status == OnDeviceModelStatus.AVAILABLE -> "available"
                    status == OnDeviceModelStatus.DOWNLOADING -> "downloading"
                    status == OnDeviceModelStatus.DOWNLOADABLE -> "downloadable"
                    else -> "unavailable"
                }
            } catch (e: Throwable) {
                payload["state"] = "unavailable"
                payload["error"] = e.message ?: e.javaClass.simpleName
            }
            result.success(payload)
        }
    }

    @OptIn(PublicPreviewAPI::class)
    private fun handleDownloadOnDeviceModel(result: Result) {
        if (!firebaseConfigured()) {
            result.error("AI_UNAVAILABLE", "Firebase is not configured on this build", null)
            return
        }
        if (downloadJob?.isActive == true) {
            result.success(hashMapOf<String, Any>("started" to false, "state" to "downloading"))
            return
        }
        downloadError = null
        downloadDone = false
        downloadedBytes = 0L
        downloadJob = scope.launch {
            try {
                FirebaseAIOnDevice.download().collect { st ->
                    when (st) {
                        is DownloadStatus.DownloadStarted -> totalBytes = st.bytesToDownload
                        is DownloadStatus.DownloadInProgress -> downloadedBytes = st.totalBytesDownloaded
                        is DownloadStatus.DownloadCompleted -> downloadDone = true
                        is DownloadStatus.DownloadFailed -> downloadError = "Download failed (check the internet connection and free storage)"
                        else -> {}
                    }
                }
            } catch (e: Throwable) {
                downloadError = e.message ?: e.javaClass.simpleName
            }
        }
        result.success(hashMapOf<String, Any>("started" to true, "state" to "downloading"))
    }

    private fun handleParseExpenseText(call: MethodCall, result: Result) {
        val prompt = call.argument<String>("prompt") ?: ""
        val mode = call.argument<String>("mode") ?: "PREFER_ON_DEVICE"
        val cloudModel = call.argument<String>("cloudFallbackModel") ?: CLOUD_FALLBACK_MODEL
        val maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 512
        val receiptBase64 = call.argument<String>("receiptBase64")
        // Recorded voice (AAC/M4A, WAV...) as inline audio data: always answered by the cloud model.
        val audioBase64 = call.argument<String>("audioBase64")
        val audioMimeType = call.argument<String>("audioMimeType") ?: "audio/mp4"
        val audioBytes: ByteArray? = if (!audioBase64.isNullOrEmpty()) {
            try {
                Base64.decode(audioBase64, Base64.DEFAULT)
            } catch (e: Exception) {
                null
            }
        } else null

        if (!firebaseConfigured()) {
            result.error("AI_UNAVAILABLE", "Firebase is not configured on this build", null)
            return
        }

        val bitmap: Bitmap? = if (!receiptBase64.isNullOrEmpty()) {
            try {
                val bytes = Base64.decode(receiptBase64, Base64.DEFAULT)
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } catch (e: Exception) {
                null
            }
        } else null

        scope.launch {
            val started = SystemClock.elapsedRealtime()
            try {
                val payload = runHybridInference(
                    prompt, bitmap, mode, cloudModel, maxOutputTokens, audioBytes, audioMimeType,
                )
                val elapsed = SystemClock.elapsedRealtime() - started
                result.success(payload + mapOf("latencyMs" to elapsed))
            } catch (e: Throwable) {
                result.error("AI_UNAVAILABLE", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    /**
     * Genuine Firebase AI Logic call with a model fallback chain.
     *
     * The first attempt uses the requested model with `OnDeviceConfig(mode = ...)` (Gemini Nano
     * via AICore when the mode allows it). If it fails or times out, the remaining models
     * (`gemini-3.1-flash-lite`, then `gemini-3.8-flash`) are tried cloud-only, one short attempt
     * each. A model that rejects `thinkingConfig` with a generic 400 "invalid argument" is retried
     * once without it. The SDK reports where inference actually ran through `response.inferenceSource`.
     */
    @OptIn(PublicPreviewAPI::class)
    private suspend fun runHybridInference(
        prompt: String,
        bitmap: Bitmap?,
        mode: String,
        cloudModel: String,
        tokenLimit: Int,
        audioBytes: ByteArray? = null,
        audioMimeType: String = "audio/mp4",
    ): Map<String, Any> {
        // Audio is multimodal input: Gemini Nano (AICore) cannot take it, so it is cloud only.
        val requestedMode = if (audioBytes != null) InferenceMode.ONLY_IN_CLOUD else when (mode) {
            "ONLY_ON_DEVICE" -> InferenceMode.ONLY_ON_DEVICE
            "ONLY_IN_CLOUD" -> InferenceMode.ONLY_IN_CLOUD
            "PREFER_IN_CLOUD" -> InferenceMode.PREFER_IN_CLOUD
            else -> InferenceMode.PREFER_ON_DEVICE
        }

        val chain = mutableListOf(cloudModel)
        for (m in listOf(CLOUD_FALLBACK_MODEL, SLOW_CLOUD_MODEL)) if (m !in chain) chain.add(m)

        var lastError: Throwable = IllegalStateException("No Gemini model answered")
        for ((index, model) in chain.withIndex()) {
            // Only the first attempt may use the device; fallbacks are cloud-only. An on-device-only
            // request has nothing to fall back to, so it stays a single attempt.
            val attemptMode = if (index == 0) requestedMode else InferenceMode.ONLY_IN_CLOUD
            if (index > 0 && requestedMode == InferenceMode.ONLY_ON_DEVICE) break
            val timeoutMs = when {
                audioBytes != null -> AUDIO_ATTEMPT_TIMEOUT_MS
                attemptMode == InferenceMode.ONLY_IN_CLOUD -> CLOUD_ATTEMPT_TIMEOUT_MS
                else -> ON_DEVICE_ATTEMPT_TIMEOUT_MS
            }
            try {
                return try {
                    withTimeout(timeoutMs) { attempt(prompt, bitmap, attemptMode, model, tokenLimit, true, audioBytes, audioMimeType) }
                } catch (first: Throwable) {
                    if (!rejectsThinkingConfig(first)) throw first
                    withTimeout(timeoutMs) { attempt(prompt, bitmap, attemptMode, model, tokenLimit, false, audioBytes, audioMimeType) }
                }
            } catch (e: Throwable) {
                lastError = e
            }
        }
        throw lastError
    }

    /** Generic 400 "invalid argument" (or an explicit thinking error): the model rejects thinkingConfig. */
    private fun rejectsThinkingConfig(e: Throwable): Boolean {
        val msg = (e.message ?: "").lowercase()
        return msg.contains("thinking") || msg.contains("invalid argument")
    }

    @OptIn(PublicPreviewAPI::class)
    private suspend fun attempt(
        prompt: String,
        bitmap: Bitmap?,
        inferenceMode: InferenceMode,
        modelName: String,
        tokenLimit: Int,
        thinkingOff: Boolean,
        audioBytes: ByteArray? = null,
        audioMimeType: String = "audio/mp4",
    ): Map<String, Any> {
        // Expense parsing needs no reasoning. Thinking models (Gemini 2.5+/3.x) would otherwise spend
        // the small output budget on hidden thinking tokens and return truncated JSON.
        val cloudConfig = generationConfig {
            responseMimeType = "application/json"
            maxOutputTokens = tokenLimit
            if (thinkingOff) thinkingConfig = thinkingConfig { thinkingBudget = 0 }
        }
        val onDeviceConfig = OnDeviceConfig(
            mode = inferenceMode,
            maxOutputTokens = tokenLimit,
        )

        val model = Firebase.ai(backend = GenerativeBackend.googleAI()).generativeModel(
            modelName = modelName,
            generationConfig = cloudConfig,
            onDeviceConfig = onDeviceConfig,
        )

        val response = if (audioBytes != null) {
            // The recorded speech goes in as inline audio next to the instructions.
            model.generateContent(content {
                inlineData(audioBytes, audioMimeType)
                text(prompt)
            })
        } else if (bitmap != null) {
            // On-device inference accepts a single image; multimodal requests also work in the cloud.
            model.generateContent(content {
                image(bitmap)
                text(prompt)
            })
        } else {
            model.generateContent(prompt)
        }

        // The SDK's InferenceSource prints as "On Device" / "In Cloud" (with a space), so compare the
        // constant itself: a string match on "ON_DEVICE" labelled real Gemini Nano answers as cloud.
        val source = response.inferenceSource
        val onDevice = source == InferenceSource.ON_DEVICE ||
            source.toString().replace(" ", "_").contains("ON_DEVICE", ignoreCase = true)
        return mapOf(
            "rawJson" to (response.text ?: "{}"),
            "inferenceSource" to if (onDevice) "on_device" else "in_cloud",
            "modelInfo" to if (onDevice) {
                "Gemini Nano (AICore, on-device via Firebase AI Logic)"
            } else {
                "$modelName (Firebase AI Logic Cloud)"
            },
        )
    }
}
