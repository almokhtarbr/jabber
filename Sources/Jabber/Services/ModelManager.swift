import Foundation
import WhisperKit

@MainActor
@Observable
final class ModelManager {
    static let shared = ModelManager()

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

    private let repoName = "argmaxinc/whisperkit-coreml"

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

    func downloadModel(_ modelId: String) async throws {
        guard let idx = models.firstIndex(where: { $0.id == modelId }) else { return }

        models[idx].isDownloading = true
        models[idx].downloadProgress = 0

        defer {
            models[idx].isDownloading = false
        }

        _ = try await WhisperKit.download(
            variant: modelId,
            progressCallback: { [weak self] progress in
                Task { @MainActor in
                    guard let self,
                          let idx = self.models.firstIndex(where: { $0.id == modelId }) else { return }
                    self.models[idx].downloadProgress = progress.fractionCompleted
                }
            }
        )

        models[idx].isDownloaded = true
        models[idx].downloadProgress = 1.0
    }

    func deleteModel(_ modelId: String) throws {
        guard let modelPath = modelFolderPath(for: modelId) else { return }

        if FileManager.default.fileExists(atPath: modelPath.path) {
            try FileManager.default.removeItem(at: modelPath)
        }

        refreshModels()

        if UserDefaults.standard.string(forKey: "selectedModel") == modelId {
            let firstDownloaded = downloadedModels.first?.id ?? "base"
            UserDefaults.standard.set(firstDownloaded, forKey: "selectedModel")
        }
    }

    func ensureDefaultModelDownloaded() async {
        if hasAnyDownloadedModel { return }

        do {
            try await downloadModel("base")
            UserDefaults.standard.set("base", forKey: "selectedModel")
        } catch {
            print("[ModelManager] Failed to download base model: \(error)")
        }
    }

    private func modelsBaseURL() -> URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs
            .appendingPathComponent("huggingface")
            .appendingPathComponent("models")
            .appendingPathComponent(repoName)
    }

    private func modelFolderPath(for modelId: String) -> URL? {
        guard let base = modelsBaseURL() else { return nil }

        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return nil }

        do {
            let contents = try fm.contentsOfDirectory(atPath: base.path)
            for folder in contents {
                if folder.contains(modelId) || folder.hasSuffix("-\(modelId)") {
                    return base.appendingPathComponent(folder)
                }
            }
        } catch {
            return nil
        }
        return nil
    }

    private func installedModelIds() -> [String] {
        guard let base = modelsBaseURL() else { return [] }

        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return [] }

        do {
            let contents = try fm.contentsOfDirectory(atPath: base.path)
            return modelDefinitions.compactMap { def in
                let matchesAny = contents.contains { folder in
                    folder.contains(def.id) || folder.hasSuffix("-\(def.id)")
                }
                return matchesAny ? def.id : nil
            }
        } catch {
            return []
        }
    }
}
