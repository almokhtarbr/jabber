import AppKit
import Carbon
import ApplicationServices

final class OutputManager {
    enum OutputMode {
        case clipboard
        case pasteInPlace
    }

    var mode: OutputMode = .pasteInPlace

    func output(_ text: String) {
        copyToClipboard(text)

        if mode == .pasteInPlace {
            if checkAccessibilityPermission() {
                sendPaste()
            }
        }
    }

    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()

        if !trusted {
            // Prompt user to grant permission
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        return trusted
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func sendPaste() {
        // Small delay to ensure the target app is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Synthesize Cmd+V
            // Note: requires Accessibility permission
            let src = CGEventSource(stateID: .hidSystemState)

            // 'v' keycode is 0x09
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand

            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }
}
