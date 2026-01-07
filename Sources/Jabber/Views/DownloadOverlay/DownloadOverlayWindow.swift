import AppKit
import SwiftUI

@MainActor
final class DownloadOverlayWindow {
    private var window: NSPanel?

    func show() {
        if window == nil {
            createWindow()
        }
        window?.orderFront(nil)
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            window?.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.window?.orderOut(nil)
                self?.window?.alphaValue = 1
            }
        }
    }

    func updateProgress(_ progress: Double, status: String) {
        guard let contentView = window?.contentView as? NSHostingView<DownloadOverlayContent> else { return }
        contentView.rootView = DownloadOverlayContent(progress: progress, status: status)
    }

    private func createWindow() {
        guard let screen = NSScreen.main else { return }

        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 80

        let x = (screen.frame.width - windowWidth) / 2
        let y = (screen.frame.height - windowHeight) / 2

        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = DownloadOverlayContent(progress: 0, status: "Preparing...")
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight)

        panel.contentView = hostingView
        self.window = panel
    }
}

struct DownloadOverlayContent: View {
    let progress: Double
    let status: String

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                Text("Jabber")
                    .font(.headline)
            }

            VStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}
