#if os(macOS)
    import LaunchBayCore
    import SwiftUI

    struct RootView: View {
        @EnvironmentObject private var model: AppModel

        var body: some View {
            NavigationSplitView {
                List(AppModel.Section.allCases, selection: $model.selectedSection) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
                .navigationTitle("Containers")
                .safeAreaInset(edge: .bottom) {
                    SidebarSystemStatus()
                        .padding(10)
                }
            } detail: {
                content
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let operation = model.activeOperation {
                        ProgressView()
                            .controlSize(.small)
                            .help(operation)
                    }

                    Button {
                        Task { await model.refreshAll() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing || model.activeOperation != nil || !model.isCLIInstalled)
                }
            }
            .sheet(
                isPresented: $model.presentRunContainer,
                onDismiss: { model.clearRunContainerRequest() }
            ) {
                RunContainerSheet(initialImageReference: model.requestedRunImageReference)
                    .environmentObject(model)
            }
            .sheet(isPresented: $model.presentPullImage) {
                PullImageSheet()
                    .environmentObject(model)
            }
            .sheet(isPresented: $model.presentBuildImage) {
                BuildImageSheet()
                    .environmentObject(model)
            }
            .alert(item: $model.alertMessage) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }

        @ViewBuilder
        private var content: some View {
            switch model.selectedSection ?? .dashboard {
            case .dashboard:
                DashboardView()
            case .containers:
                ContainersView()
            case .images:
                ImagesView()
            case .activity:
                ActivityView()
            case .settings:
                SettingsView()
            }
        }
    }

    private struct SidebarSystemStatus: View {
        @EnvironmentObject private var model: AppModel

        var body: some View {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.caption.weight(.semibold))
                    if let version = model.systemStatus.version {
                        Text("container \(version)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }

        private var statusTitle: String {
            if !model.isCLIInstalled { return "CLI not installed" }
            switch model.systemStatus.state {
            case .running: return "System running"
            case .notRunning, .unregistered: return "System stopped"
            case .unavailable: return "Unavailable"
            case .unknown: return "Status unknown"
            }
        }

        private var statusColor: Color {
            switch model.systemStatus.state {
            case .running: .green
            case .notRunning, .unregistered: .orange
            case .unavailable, .unknown: .secondary
            }
        }
    }
#endif
