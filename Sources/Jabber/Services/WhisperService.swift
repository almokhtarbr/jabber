import Foundation
import WhisperKit

actor WhisperService {
    private var whisperKit: WhisperKit?
    private var isLoading = false

    enum State: Sendable {
        case notReady
        case downloading(progress: Double, status: String)
        case loading
        case ready
        case error(String)
    }

    private nonisolated(unsafe) var stateCallback: (@Sendable (State) -> Void)?

    nonisolated func setStateCallback(_ callback: @escaping @Sendable (State) -> Void) {
        stateCallback = callback
    }

    nonisolated var isReady: Bool {
        _isReady
    }

    private nonisolated(unsafe) var _isReady = false

    /// Vocabulary prompt to bias transcription toward specific terms (names, jargon, etc.)
    private var vocabularyPrompt: String = ""

    func setVocabularyPrompt(_ prompt: String) {
        vocabularyPrompt = prompt
    }

    func ensureModelLoaded() async throws {
        if whisperKit != nil { return }
        try await loadModel()
    }

    func transcribe(samples: [Float]) async throws -> String {
        let kit = try await getWhisperKit()

        var options = DecodingOptions()
        options.language = "en"  // Force English since we're using multilingual model

        if !vocabularyPrompt.isEmpty, let tokenizer = kit.tokenizer {
            let tokens = tokenizer.encode(text: vocabularyPrompt).filter { $0 < 51865 }
            if !tokens.isEmpty {
                options.promptTokens = tokens
            }
        }

        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)

        return results.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadModel() async throws {
        guard !isLoading else {
            while isLoading {
                try await Task.sleep(for: .milliseconds(100))
            }
            if whisperKit != nil { return }
            throw WhisperError.loadFailed
        }

        isLoading = true
        defer { isLoading = false }

        let selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "base"

        let modelFolder: URL
        if let existingFolder = localModelFolder(for: selectedModel) {
            modelFolder = existingFolder
        } else {
            modelFolder = try await WhisperKit.download(
                variant: selectedModel,
                progressCallback: { [weak self] progress in
                    let pct = progress.fractionCompleted
                    Task { @MainActor in
                        self?.stateCallback?(.downloading(progress: pct, status: "Downloading \(selectedModel)... \(Int(pct * 100))%"))
                    }
                }
            )
        }

        stateCallback?(.loading)

        let kit = try await WhisperKit(modelFolder: modelFolder.path)

        whisperKit = kit
        _isReady = true
        stateCallback?(.ready)
    }

    private func getWhisperKit() async throws -> WhisperKit {
        if let kit = whisperKit {
            return kit
        }
        try await loadModel()
        guard let kit = whisperKit else {
            throw WhisperError.loadFailed
        }
        return kit
    }

    private nonisolated func localModelFolder(for modelId: String) -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let base = docs
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent("argmaxinc/whisperkit-coreml")

        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return nil }

        guard let contents = try? fm.contentsOfDirectory(atPath: base.path) else { return nil }

        for folder in contents {
            if folder.hasSuffix("-\(modelId)") {
                let folderURL = base.appendingPathComponent(folder)
                let configPath = folderURL.appendingPathComponent("config.json")
                if fm.fileExists(atPath: configPath.path) {
                    return folderURL
                }
            }
        }
        return nil
    }
}

enum WhisperError: Error {
    case loadFailed
    case transcriptionFailed
    case modelNotReady
}
