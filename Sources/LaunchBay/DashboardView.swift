#if os(macOS)
    import LaunchBayCore
    import SwiftUI

    struct DashboardView: View {
        @EnvironmentObject private var model: AppModel

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if !model.hostCompatibility.supportsAppleContainerRuntime {
                        compatibilityWarning
                    }

                    if !model.isCLIInstalled {
                        missingCLI
                    } else if !model.isSystemRunning {
                        stoppedSystem
                    } else {
                        metrics
                        quickActions
                        recentContainers
                    }
                }
                .padding(24)
                .frame(maxWidth: 1_000, alignment: .leading)
            }
            .navigationTitle("Dashboard")
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: 5) {
                Text("LaunchBay")
                    .font(.largeTitle.bold())
                Text("A focused macOS interface for Apple’s lightweight Linux container runtime.")
                    .foregroundStyle(.secondary)
            }
        }

        private var compatibilityWarning: some View {
            GroupBox {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Apple container requires an Apple silicon Mac running macOS 26 or newer.")
                            .font(.headline)
                        Text(
                            "Run LaunchBay on a supported Apple silicon Mac to manage images and containers."
                        )
                        .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .padding(4)
            }
        }

        private var missingCLI: some View {
            ContentUnavailableView {
                Label("Apple container is not installed", systemImage: "shippingbox.and.arrow.backward")
            } description: {
                Text(
                    "Install Apple’s signed container package, or select an existing container executable in Settings."
                )
            } actions: {
                Button("Open Settings") {
                    model.selectedSection = .settings
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(minHeight: 330)
        }

        private var stoppedSystem: some View {
            ContentUnavailableView {
                Label("Container system is stopped", systemImage: "power")
            } description: {
                Text("Start Apple’s background services before managing images and containers.")
            } actions: {
                Button("Start System") {
                    Task { _ = await model.startSystem() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.activeOperation != nil)
            }
            .frame(minHeight: 330)
        }

        private var metrics: some View {
            HStack(spacing: 14) {
                MetricCard(
                    title: "Running",
                    value: String(model.runningContainerCount),
                    systemImage: "play.circle",
                    caption: "of \(model.containers.count) containers"
                )
                MetricCard(
                    title: "Images",
                    value: String(model.images.count),
                    systemImage: "opticaldiscdrive",
                    caption: imageSizeCaption
                )
                MetricCard(
                    title: "Runtime",
                    value: model.systemStatus.version ?? "Unknown",
                    systemImage: "cpu",
                    caption: model.systemStatus.build
                )
            }
        }

        private var imageSizeCaption: String? {
            let bytes = model.images.compactMap(\.totalSizeBytes).reduce(0, +)
            guard bytes > 0 else { return nil }
            return bytes.nativeContainerFileSize
        }

        private var quickActions: some View {
            GroupBox("Quick actions") {
                HStack(spacing: 12) {
                    Button {
                        model.requestRunContainer()
                    } label: {
                        Label("Run Container", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.presentPullImage = true
                    } label: {
                        Label("Pull Image", systemImage: "arrow.down.circle")
                    }

                    Button {
                        model.presentBuildImage = true
                    } label: {
                        Label("Build Dockerfile", systemImage: "hammer")
                    }

                    Spacer()

                    Button(role: .destructive) {
                        Task { _ = await model.stopSystem() }
                    } label: {
                        Label("Stop System", systemImage: "power")
                    }
                }
                .padding(.vertical, 8)
                .disabled(!model.canManageResources)
            }
        }

        private var recentContainers: some View {
            GroupBox("Containers") {
                if model.containers.isEmpty {
                    Text("No containers yet. Pull an OCI image and run it to get started.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 0) {
                        ForEach(model.containers.prefix(6)) { container in
                            HStack(spacing: 12) {
                                Image(systemName: container.state == .running ? "shippingbox.fill" : "shippingbox")
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(container.name)
                                        .fontWeight(.medium)
                                    Text(container.imageReference)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                StatusBadge(state: container.state)
                            }
                            .padding(.vertical, 9)
                            if container.id != model.containers.prefix(6).last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
#endif
