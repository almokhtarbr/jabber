import Foundation
import SwiftUI

@MainActor
final class WaveformView: ObservableObject {
    @Published private(set) var levels: [Float] = []
    @Published private(set) var isProcessing = false

    private let maxSamples = 60

    func addLevel(_ level: Float) {
        levels.append(level)
        if levels.count > maxSamples {
            levels.removeFirst()
        }
    }

    func reset() {
        levels.removeAll()
        isProcessing = false
    }

    func showProcessing() {
        isProcessing = true
    }
}
