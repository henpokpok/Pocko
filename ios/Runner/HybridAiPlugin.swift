import Flutter
import UIKit

#if canImport(FirebaseCore)
import FirebaseCore
#endif

// Gemini cloud fallback: the stable `GenerativeModel` API of the `FirebaseAILogic` product of
// firebase-ios-sdk (Swift Package Manager only; the Runner target links it directly).
// firebase-ios-sdk 13.0 removed the interim `HybridModel` / `GenerativeModelSession` /
// `SystemLanguageModel` types, so hybrid routing is done here instead.
#if canImport(FirebaseAILogic)
import FirebaseAILogic
#endif

// On-device inference: Apple's own Foundation Models framework (iOS 26+, Apple Intelligence).
#if canImport(FoundationModels)
import FoundationModels
#endif

/**
 * HybridAiPlugin
 *
 * Flutter MethodChannel bridge for hybrid expense parsing on iOS / iPadOS:
 * Apple Foundation Models on-device first, Gemini cloud (Firebase AI Logic) as the fallback.
 *
 * Contract with Dart (`lib/services/hybrid_ai/hybrid_ai_service.dart`):
 * - `checkModelStatus` -> { isAvailable, status, modelInfo }
 * - `parseExpenseText` -> { rawJson, inferenceSource: "on_device" | "in_cloud", latencyMs, modelInfo }
 *
 * The bridge NEVER fabricates a result: when neither runtime can answer it replies
 * `AI_UNAVAILABLE` and Dart switches to its clearly labelled (`isSimulated`) offline engine.
 *
 * On-device inference on Apple platforms is text-only, single-turn and foreground-only, so image
 * (receipt) requests always go to the cloud model.
 */
public class HybridAiPlugin: NSObject, FlutterPlugin {

    private static let channelName = "com.hybridtrip.ai/inference"

    /// Fast default for structured extraction (measured 1-2 s). The slower gemini-3.8-flash is the
    /// fallback, so a hung or retired model never costs more than one short attempt.
    private static let fastCloudModel = "gemini-3.1-flash-lite"
    private static let slowCloudModel = "gemini-3.8-flash"
    private static let cloudAttemptTimeout: TimeInterval = 8
    /// Recorded speech (inline audio) is uploaded and transcribed in one cloud call.
    private static let audioAttemptTimeout: TimeInterval = 15

    private enum HybridAiError: Error, CustomStringConvertible {
        case unavailable(String)
        var description: String {
            switch self {
            case .unavailable(let message): return message
            }
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: channelName, binaryMessenger: registrar.messenger())
        let instance = HybridAiPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "checkModelStatus":
            handleCheckModelStatus(result: result)
        case "parseExpenseText":
            guard let args = call.arguments as? [String: Any] else {
                result(FlutterError(code: "INVALID_ARGS", message: "Arguments must be a Map", details: nil))
                return
            }
            handleParseExpenseText(args: args, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Capabilities

    private static func firebaseConfigured() -> Bool {
        #if canImport(FirebaseCore)
        return FirebaseApp.app() != nil
        #else
        return false
        #endif
    }

    /// Whether the Gemini cloud runtime can be used (package linked and Firebase configured).
    private static func cloudReady() -> Bool {
        #if canImport(FirebaseAILogic)
        return firebaseConfigured()
        #else
        return false
        #endif
    }

    /// Whether Apple Foundation Models can answer right now (iOS 26+, Apple Intelligence on).
    private static func onDeviceReady() -> Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    private func handleCheckModelStatus(result: @escaping FlutterResult) {
        let onDevice = Self.onDeviceReady()
        let cloud = Self.cloudReady()

        let status: String
        let info: String
        if onDevice {
            status = "READY_APPLE_FM"
            info = cloud
                ? "Apple Foundation Models (on-device) with Gemini cloud fallback"
                : "Apple Foundation Models (on-device); Gemini cloud fallback is not configured"
        } else if cloud {
            status = "APPLE_INTELLIGENCE_UNAVAILABLE"
            info = "Apple Intelligence is not available (iOS 26+ with Apple Intelligence enabled). Gemini cloud only"
        } else {
            status = "FIREBASE_NOT_CONFIGURED"
            info = "No runtime available (needs iOS 26 + Apple Intelligence, or Firebase configured). Simulated engine will be used"
        }

        result([
            "isAvailable": onDevice || cloud,
            "status": status,
            "modelInfo": info,
        ])
    }

    // MARK: - Inference

    private func handleParseExpenseText(args: [String: Any], result: @escaping FlutterResult) {
        let prompt = args["prompt"] as? String ?? ""
        let mode = args["mode"] as? String ?? "PREFER_ON_DEVICE"
        let cloudModel = args["cloudFallbackModel"] as? String ?? Self.fastCloudModel
        let maxTokens = args["maxOutputTokens"] as? Int
        let receiptBase64 = args["receiptBase64"] as? String
        // Recorded voice (AAC/M4A, WAV...) as inline audio: always answered by the cloud model.
        var audioData: Data?
        if let b64 = args["audioBase64"] as? String, !b64.isEmpty {
            audioData = Data(base64Encoded: b64)
        }
        let audioMimeType = args["audioMimeType"] as? String ?? "audio/mp4"

        let started = CACurrentMediaTime()
        Task {
            do {
                let outcome = try await Self.infer(
                    prompt: prompt,
                    mode: mode,
                    cloudModel: cloudModel,
                    maxTokens: maxTokens,
                    receiptBase64: receiptBase64,
                    audioData: audioData,
                    audioMimeType: audioMimeType
                )
                let elapsed = Int((CACurrentMediaTime() - started) * 1000)
                let payload: [String: Any] = [
                    "rawJson": outcome.text,
                    "inferenceSource": outcome.onDevice ? "on_device" : "in_cloud",
                    "latencyMs": elapsed,
                    "modelInfo": outcome.modelInfo,
                ]
                DispatchQueue.main.async { result(payload) }
            } catch {
                DispatchQueue.main.async {
                    result(FlutterError(code: "AI_UNAVAILABLE", message: "\(error)", details: nil))
                }
            }
        }
    }

    private struct Outcome {
        let text: String
        let onDevice: Bool
        let modelInfo: String
    }

    /// Routes one request. Modes: ONLY_ON_DEVICE, ONLY_IN_CLOUD, PREFER_IN_CLOUD, otherwise
    /// PREFER_ON_DEVICE (Apple Foundation Models first, Gemini cloud when it cannot answer).
    private static func infer(
        prompt: String,
        mode: String,
        cloudModel: String,
        maxTokens: Int?,
        receiptBase64: String?,
        audioData: Data?,
        audioMimeType: String
    ) async throws -> Outcome {
        // Apple on-device inference is text-only: photos and audio always use the cloud model.
        let hasImage = receiptBase64?.isEmpty == false || audioData != nil

        func device() async throws -> Outcome {
            let text = try await runOnDevice(prompt: prompt, maxTokens: maxTokens)
            return Outcome(text: text, onDevice: true, modelInfo: "Apple Foundation Models (on-device)")
        }
        func cloud() async throws -> Outcome {
            let (text, used) = try await runCloud(
                prompt: prompt,
                requestedModel: cloudModel,
                maxTokens: maxTokens,
                receiptBase64: receiptBase64,
                audioData: audioData,
                audioMimeType: audioMimeType
            )
            return Outcome(text: text, onDevice: false, modelInfo: "\(used) (Firebase AI Logic Cloud)")
        }

        // Apple on-device is text-only: receipt photos always use the cloud model.
        if mode == "ONLY_IN_CLOUD" || hasImage { return try await cloud() }
        if mode == "ONLY_ON_DEVICE" { return try await device() }
        if mode == "PREFER_IN_CLOUD" {
            do { return try await cloud() } catch { return try await device() }
        }
        // PREFER_ON_DEVICE
        if onDeviceReady() {
            do { return try await device() } catch { /* fall through to the cloud */ }
        }
        return try await cloud()
    }

    /// Apple Foundation Models (iOS 26+). Text in, text out; the Dart side extracts the JSON.
    private static func runOnDevice(prompt: String, maxTokens: Int?) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw HybridAiError.unavailable("Apple Intelligence is not available on this device")
            }
            // One session per request: on-device inference is single-turn.
            let session = LanguageModelSession(model: model)
            let options = GenerationOptions(maximumResponseTokens: maxTokens)
            let response = try await session.respond(to: prompt, options: options)
            return response.content
        }
        #endif
        throw HybridAiError.unavailable("Apple Foundation Models need iOS 26 or later")
    }

    /// Gemini through Firebase AI Logic. Tries the requested model, then the other fast / slow
    /// model, one short attempt each. Thinking is switched off (expense parsing needs no
    /// reasoning; thinking models would spend the output budget on hidden tokens and return
    /// truncated JSON); a model that rejects `thinkingConfig` is retried once without it.
    private static func runCloud(
        prompt: String,
        requestedModel: String,
        maxTokens: Int?,
        receiptBase64: String?,
        audioData: Data?,
        audioMimeType: String
    ) async throws -> (String, String) {
        #if canImport(FirebaseAILogic)
        guard firebaseConfigured() else {
            throw HybridAiError.unavailable("Firebase is not configured on this build")
        }
        let ai = FirebaseAI.firebaseAI(backend: .googleAI())

        var chain = [requestedModel]
        for model in [fastCloudModel, slowCloudModel] where !chain.contains(model) {
            chain.append(model)
        }

        var image: UIImage?
        if let b64 = receiptBase64, !b64.isEmpty, let data = Data(base64Encoded: b64) {
            image = UIImage(data: data)
        }

        func attempt(_ model: String, thinkingOff: Bool) async throws -> String {
            let config = GenerationConfig(
                maxOutputTokens: maxTokens,
                responseMIMEType: "application/json",
                thinkingConfig: thinkingOff ? ThinkingConfig(thinkingBudget: 0) : nil
            )
            let generative = ai.generativeModel(
                modelName: model,
                generationConfig: config,
                requestOptions: RequestOptions(
                    timeout: audioData != nil ? audioAttemptTimeout : cloudAttemptTimeout
                )
            )
            let response: GenerateContentResponse
            if let audio = audioData {
                // The recorded speech goes in as inline audio next to the instructions.
                response = try await generative.generateContent(
                    InlineDataPart(data: audio, mimeType: audioMimeType),
                    prompt
                )
            } else if let image = image {
                response = try await generative.generateContent(image, prompt)
            } else {
                response = try await generative.generateContent(prompt)
            }
            guard let text = response.text, !text.isEmpty else {
                throw HybridAiError.unavailable("\(model) returned an empty answer")
            }
            return text
        }

        var lastError: Error = HybridAiError.unavailable("No Gemini model answered")
        for model in chain {
            do {
                return (try await attempt(model, thinkingOff: true), model)
            } catch {
                lastError = error
                let message = "\(error)".lowercased()
                // Generic 400 "invalid argument" / "thinking": the model rejects thinkingConfig.
                if message.contains("thinking") || message.contains("invalid argument") {
                    do { return (try await attempt(model, thinkingOff: false), model) } catch { lastError = error }
                }
            }
        }
        throw lastError
        #else
        throw HybridAiError.unavailable("FirebaseAILogic (Swift Package Manager) is not linked")
        #endif
    }
}
