#if os(macOS)
    import AppKit
    import LaunchBayCore
    import SwiftUI

    struct BuildImageSheet: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.dismiss) private var dismiss

        @State private var configuration = BuildImageConfiguration(platform: "linux/arm64")

        var body: some View {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Build Dockerfile")
                        .font(.title2.bold())
                    Text("Build an OCI image with Apple container’s BuildKit integration.")
                        .foregroundStyle(.secondary)
                }

                Form {
                    LabeledContent("Build context") {
                        HStack {
                            Text(configuration.contextPath.isEmpty ? "Not selected" : configuration.contextPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(configuration.contextPath.isEmpty ? .secondary : .primary)
                            Button("Choose…") { chooseContext() }
                        }
                    }

                    LabeledContent("Dockerfile") {
                        HStack {
                            Text(configuration.dockerfilePath ?? "Use Dockerfile or Containerfile from context")
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(configuration.dockerfilePath == nil ? .secondary : .primary)
                            Button("Choose…") { chooseDockerfile() }
                            if configuration.dockerfilePath != nil {
                                Button("Clear") { configuration.dockerfilePath = nil }
                            }
                        }
                    }

                    TextField("Image tag", text: $configuration.tag, prompt: Text("my-app:latest"))
                    TextField(
                        "Platform",
                        text: Binding(
                            get: { configuration.platform ?? "" },
                            set: { configuration.platform = $0.isEmpty ? nil : $0 }
                        ))
                    Toggle("Pull newer base images", isOn: $configuration.pullBaseImages)
                    Toggle("Disable build cache", isOn: $configuration.noCache)
                }
                .formStyle(.grouped)

                HStack {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Build") {
                        Task {
                            if await model.buildImage(configuration) {
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        configuration.contextPath.trimmed.isEmpty
                            || configuration.tag.trimmed.isEmpty
                            || model.activeOperation != nil
                    )
                }
            }
            .padding(20)
            .frame(width: 620, height: 430)
        }

        private func chooseContext() {
            let panel = NSOpenPanel()
            panel.title = "Choose build context"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            configuration.contextPath = url.path
        }

        private func chooseDockerfile() {
            let panel = NSOpenPanel()
            panel.title = "Choose Dockerfile or Containerfile"
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowsMultipleSelection = false
            guard panel.runModal() == .OK, let url = panel.url else { return }
            configuration.dockerfilePath = url.path
            if configuration.contextPath.isEmpty {
                configuration.contextPath = url.deletingLastPathComponent().path
            }
        }
    }
#endif
