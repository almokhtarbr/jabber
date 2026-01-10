import Foundation
import WhisperKit
import os

struct ModelDownloadState {
    enum Phase: String {
        case started
        case progress
        case finished
        case failed
    }

    let modelId: String
    let progress: Double
    let status: String
    let phase: Phase
    let errorDescription: String?
}

@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()
    private let logger = Logger(subsystem: "com.rselbach.jabber", category: "ModelManager")
    private static let downloadWaitTimeout: Duration = .seconds(600)

    struct Model: Identifiable {
        let id: String
        let name: String
        let description: String
        let sizeHint: String
        var isDownloaded: Bool
        var isDownloading: Bool
        var downloadProgress: Double
    }

    private(set) var models: [Model] = []

    private let modelDefinitions: [(id: String, name: String, description: String, sizeHint: String)] = [
        ("tiny", "Tiny", "Fastest, lowest accuracy", "~40MB"),
        ("base", "Base", "Balanced speed/accuracy", "~140MB"),
        ("small", "Small", "Good accuracy", "~460MB"),
        ("medium", "Medium", "Very accurate", "~1.5GB"),
        ("large-v3", "Large v3", "Best accuracy", "~3GB")
    ]

    private init() {
        refreshModels()
    }

    var downloadedModels: [Model] {
        models.filter { $0.isDownloaded }
    }

    var hasAnyDownloadedModel: Bool {
        !downloadedModels.isEmpty
    }

    func refreshModels() {
        let downloadedIds = Set(installedModelIds())
        models = modelDefinitions.map { def in
            Model(
                id: def.id,
                name: def.name,
                description: def.description,
                sizeHint: def.sizeHint,
                isDownloaded: downloadedIds.contains(def.id),
                isDownloading: false,
                downloadProgress: 0
            )
        }
    }

    func ensureModelDownloaded(_ modelId: String) async throws -> URL {
        if let existing = Constants.ModelPaths.localModelFolder(for: modelId) {
            return existing
        }
        return try await downloadModel(modelId)
    }

    @discardableResult
    func downloadModel(_ modelId: String) async throws -> URL {
        // Verify model exists before starting
        guard models.contains(where: { $0.id == modelId }) else {
            logger.warning("Attempted to download non-existent model: \(modelId)")
            throw ModelError.modelNotFound(modelId: modelId)
        }

        if let existing = Constants.ModelPaths.localModelFolder(for: modelId) {
            if let idx = models.firstIndex(where: { $0.id == modelId }) {
                models[idx].isDownloaded = true
                models[idx].isDownloading = false
                models[idx].downloadProgress = 1.0
            }
            return existing
        }

        // Set initial download state
        guard let idx = models.firstIndex(where: { $0.id == modelId }) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        if models[idx].isDownloading {
            try await waitForDownloadToFinish(modelId: modelId)
            if let existing = Constants.ModelPaths.localModelFolder(for: modelId) {
                return existing
            }
            throw ModelError.modelNotFound(modelId: modelId)
        }

        let modelName = models[idx].name
        models[idx].isDownloading = true
        models[idx].downloadProgress = 0

        NotificationCenter.default.post(
            name: Constants.Notifications.modelDownloadStateDidChange,
            object: ModelDownloadState(
                modelId: modelId,
                progress: 0,
                status: "Downloading \(modelName)... 0%",
                phase: .started,
                errorDescription: nil
            )
        )

        defer {
            // Always clear downloading state, even on error
            if let idx = models.firstIndex(where: { $0.id == modelId }) {
                models[idx].isDownloading = false
            }
        }

        let modelFolder: URL
        do {
            modelFolder = try await WhisperKit.download(
                variant: modelId,
                progressCallback: { [weak self] progress in
                    Task { @MainActor in
                        guard let self else { return }
                        // Look up index each time to avoid stale references
                        if let idx = self.models.firstIndex(where: { $0.id == modelId }) {
                            let pct = progress.fractionCompleted
                            self.models[idx].downloadProgress = pct
                            NotificationCenter.default.post(
                                name: Constants.Notifications.modelDownloadStateDidChange,
                                object: ModelDownloadState(
                                    modelId: modelId,
                                    progress: pct,
                                    status: "Downloading \(modelName)... \(Int(pct * 100))%",
                                    phase: .progress,
                                    errorDescription: nil
                                )
                            )
                        }
                    }
                }
            )
        } catch is CancellationError {
            NotificationCenter.default.post(
                name: Constants.Notifications.modelDownloadStateDidChange,
                object: ModelDownloadState(
                    modelId: modelId,
                    progress: models[idx].downloadProgress,
                    status: "Download cancelled: \(modelName)",
                    phase: .failed,
                    errorDescription: "cancelled"
                )
            )
            throw CancellationError()
        } catch {
            NotificationCenter.default.post(
                name: Constants.Notifications.modelDownloadStateDidChange,
                object: ModelDownloadState(
                    modelId: modelId,
                    progress: models[idx].downloadProgress,
                    status: "Download failed: \(modelName)",
                    phase: .failed,
                    errorDescription: error.localizedDescription
                )
            )
            throw error
        }

        // Look up index after download completes
        if let idx = models.firstIndex(where: { $0.id == modelId }) {
            models[idx].isDownloaded = true
            models[idx].downloadProgress = 1.0
        }

        NotificationCenter.default.post(
            name: Constants.Notifications.modelDownloadStateDidChange,
            object: ModelDownloadState(
                modelId: modelId,
                progress: 1.0,
                status: "Downloaded \(modelName)",
                phase: .finished,
                errorDescription: nil
            )
        )

        return modelFolder
    }

    func deleteModel(_ modelId: String) throws {
        let currentModel = UserDefaults.standard.string(forKey: "selectedModel")

        // Prevent deleting currently selected model if it's the only one
        if currentModel == modelId && downloadedModels.count == 1 {
            throw ModelError.cannotDeleteActiveModel
        }

        guard let modelPath = Constants.ModelPaths.localModelFolder(for: modelId) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            throw ModelError.modelNotFound(modelId: modelId)
        }

        try FileManager.default.removeItem(at: modelPath)

        refreshModels()

        // Switch to another model if we deleted the selected one
        if currentModel == modelId {
            guard let firstDownloaded = downloadedModels.first?.id else {
                // This should never happen due to the guard at the top, but be safe
                logger.error("No models available after deletion, falling back to base")
                UserDefaults.standard.set("base", forKey: "selectedModel")
                return
            }
            UserDefaults.standard.set(firstDownloaded, forKey: "selectedModel")
            NotificationCenter.default.post(name: Constants.Notifications.modelDidChange, object: nil)
        }
    }

    func ensureDefaultModelDownloaded() async {
        if hasAnyDownloadedModel { return }

        do {
            try await downloadModel("base")
            UserDefaults.standard.set("base", forKey: "selectedModel")
        } catch {
            logger.error("Failed to download base model: \(error.localizedDescription)")
        }
    }

    private func installedModelIds() -> [String] {
        return modelDefinitions.compactMap { def in
            Constants.ModelPaths.localModelFolder(for: def.id) != nil ? def.id : nil
        }
    }

    private func waitForDownloadToFinish(modelId: String) async throws {
        let startTime = ContinuousClock.now
        while let idx = models.firstIndex(where: { $0.id == modelId }) {
            try Task.checkCancellation()
            guard models[idx].isDownloading else { return }
            if ContinuousClock.now - startTime > Self.downloadWaitTimeout {
                throw ModelError.downloadTimeout(modelId: modelId)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw ModelError.modelNotFound(modelId: modelId)
    }
}

enum ModelError: Error, LocalizedError {
    case cannotDeleteActiveModel
    case downloadTimeout(modelId: String)
    case modelNotFound(modelId: String)

    var errorDescription: String? {
        switch self {
        case .cannotDeleteActiveModel:
            return "Cannot delete the currently active model. Please select a different model first."
        case .downloadTimeout(let modelId):
            return "Download timed out for model '\(modelId)'."
        case .modelNotFound(let modelId):
            return "Model '\(modelId)' not found or already deleted."
        }
    }
}
