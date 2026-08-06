#if os(macOS)
    import AppKit
    import LaunchBayCore
    import SwiftUI

    struct SettingsView: View {
        @EnvironmentObject private var model: AppModel
        @Environment(\.openURL) private var openURL

        var body: some View {
            Form {
                Section("Apple container CLI") {
                    LabeledContent("Detected executable") {
                        Text(model.executablePath ?? "Not found")
                            .font(.body.monospaced())
                            .foregroundStyle(model.executablePath == nil ? .secondary : .primary)
                            .textSelection(.enabled)
                    }

                    HStack {
                        Button("Choose Executable…") {
                            chooseExecutable()
                        }
                        Button("Use Automatic Detection") {
                            Task { await model.resetExecutablePath() }
                        }
                        .disabled(model.customExecutablePath.isEmpty)
                        Spacer()
                    }

                    Text(
                        "Automatic detection checks CONTAINER_CLI_PATH, /usr/local/bin/container, /opt/homebrew/bin/container, and PATH."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Refresh") {
                    Picker("Automatic refresh", selection: $model.autoRefreshSeconds) {
                        Text("Off").tag(0.0)
                        Text("Every 2 seconds").tag(2.0)
                        Text("Every 5 seconds").tag(5.0)
                        Text("Every 10 seconds").tag(10.0)
                        Text("Every 30 seconds").tag(30.0)
                    }
                    .onChange(of: model.autoRefreshSeconds) { _, _ in
                        model.restartAutoRefresh()
                    }
                }

                Section("Host compatibility") {
                    LabeledContent("Operating system") {
                        Text(ProcessInfo.processInfo.operatingSystemVersionString)
                    }
                    LabeledContent("Architecture") {
                        Text(
                            model.hostCompatibility.isAppleSilicon ? "Apple silicon" : "Unsupported architecture")
                    }
                    LabeledContent("Runtime support") {
                        Label(
                            model.hostCompatibility.supportsAppleContainerRuntime
                                ? "Supported" : "Requires Apple silicon and macOS 26+",
                            systemImage: model.hostCompatibility.supportsAppleContainerRuntime
                                ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            model.hostCompatibility.supportsAppleContainerRuntime ? .green : .orange)
                    }
                }

                Section("Installation") {
                    Text(
                        "Apple distributes the container CLI as a signed installer package. This app does not download or elevate privileges on your behalf."
                    )
                    .foregroundStyle(.secondary)
                    Button("Open Apple container Releases") {
                        openURL(URL(string: "https://github.com/apple/container/releases")!)
                    }
                }

                Section("About") {
                    Text(
                        "LaunchBay is an independent open-source client. It is not affiliated with Apple, Docker, or OrbStack."
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .padding(.horizontal, 16)
        }

        private func chooseExecutable() {
            let panel = NSOpenPanel()
            panel.title = "Choose Apple container executable"
            panel.prompt = "Choose"
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.treatsFilePackagesAsDirectories = false
            panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task { await model.updateExecutablePath(url.path) }
        }
    }
#endif
