import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private let hotkeyManager = HotkeyManager()
    private let audioCapture = AudioCaptureService()
    private let whisperService = WhisperService()
    private let outputManager = OutputManager()
    private let overlayWindow = OverlayWindow()
    private let downloadOverlay = DownloadOverlayWindow()
    let updaterController = UpdaterController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupHotkey()

        // Hide dock icon (menu bar app only)
        NSApp.setActivationPolicy(.accessory)

        Task {
            await ModelManager.shared.ensureDefaultModelDownloaded()
            await loadModel()
        }
    }

    private func loadModel() async {
        whisperService.setStateCallback { [weak self] state in
            Task { @MainActor in
                self?.handleModelState(state)
            }
        }

        do {
            try await whisperService.ensureModelLoaded()
        } catch {
            print("Failed to load model: \(error)")
            updateStatusIcon(state: .error)
            downloadOverlay.hide()
        }
    }

    private func handleModelState(_ state: WhisperService.State) {
        switch state {
        case .notReady:
            break
        case .downloading(let progress, let status):
            downloadOverlay.show()
            downloadOverlay.updateProgress(progress, status: status)
        case .loading:
            downloadOverlay.updateProgress(1.0, status: "Loading model...")
        case .ready:
            downloadOverlay.hide()
            updateStatusIcon(state: .ready)
        case .error(let message):
            print("Model error: \(message)")
            downloadOverlay.hide()
            updateStatusIcon(state: .error)
        }
    }

    private enum AppState {
        case downloading
        case ready
        case recording
        case transcribing
        case error
    }

    private func updateStatusIcon(state: AppState) {
        let iconName: String
        switch state {
        case .downloading:
            iconName = "arrow.down.circle"
        case .ready:
            iconName = "waveform"
        case .recording:
            iconName = "waveform.circle.fill"
        case .transcribing:
            iconName = "ellipsis.circle"
        case .error:
            iconName = "exclamationmark.triangle"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Jabber")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Jabber")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 200)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(rootView: MenuBarView(updaterController: updaterController))
    }

    private func setupHotkey() {
        // Default: Option + Space (0x31 = space, optionKey = 0x0800)
        hotkeyManager.register(keyCode: 0x31, modifiers: UInt32(Carbon.optionKey))

        hotkeyManager.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startDictation()
            }
        }

        hotkeyManager.onKeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopDictationAndTranscribe()
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func startDictation() {
        guard whisperService.isReady else {
            // Model not ready yet, ignore
            return
        }

        overlayWindow.show()

        audioCapture.onAudioLevel = { [weak self] level in
            self?.overlayWindow.updateLevel(level)
        }

        do {
            try audioCapture.startCapture()
            updateStatusIcon(state: .recording)
        } catch {
            print("Failed to start audio capture: \(error)")
            overlayWindow.hide()
        }
    }

    private func stopDictationAndTranscribe() async {
        audioCapture.stopCapture()
        updateStatusIcon(state: .transcribing)

        let samples = audioCapture.currentSamples()
        guard !samples.isEmpty else {
            overlayWindow.hide()
            updateStatusIcon(state: .ready)
            return
        }

        overlayWindow.showProcessing()

        // Sync vocabulary prompt from settings
        let vocab = UserDefaults.standard.string(forKey: "vocabularyPrompt") ?? ""
        await whisperService.setVocabularyPrompt(vocab)

        do {
            let text = try await whisperService.transcribe(samples: samples)
            if !text.isEmpty {
                outputManager.output(text)
            }
        } catch {
            print("[Jabber] Transcription failed: \(error)")
        }

        overlayWindow.hide()
        updateStatusIcon(state: .ready)
    }
}
