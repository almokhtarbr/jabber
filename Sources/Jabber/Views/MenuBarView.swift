import SwiftUI

struct MenuBarView: View {
    @AppStorage("selectedModel") private var selectedModel = "base"
    @State private var modelManager = ModelManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Jabber")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Press ⌥ Space to dictate")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if modelManager.downloadedModels.isEmpty {
                    Text("No models downloaded")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    HStack {
                        Text("Model:")
                        Picker("", selection: $selectedModel) {
                            ForEach(modelManager.downloadedModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            Divider()

            HStack {
                SettingsLink {
                    Text("Settings...")
                }
                .buttonStyle(.link)

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(width: 280)
        .onAppear {
            modelManager.refreshModels()
        }
    }
}

#Preview {
    MenuBarView()
}
