#if os(macOS)
    import SwiftUI

    @main
    struct LaunchBayApp: App {
        @Environment(\.scenePhase) private var scenePhase
        @StateObject private var model = AppModel()

        var body: some Scene {
            WindowGroup("LaunchBay") {
                RootView()
                    .environmentObject(model)
                    .frame(minWidth: 980, minHeight: 640)
                    .task {
                        await model.bootstrap()
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        model.setApplicationActive(newPhase == .active)
                    }
            }
            .defaultSize(width: 1_180, height: 760)
            .commands {
                CommandGroup(after: .sidebar) {
                    Button("Refresh") {
                        Task { await model.refreshAll(force: true) }
                    }
                    .keyboardShortcut("r", modifiers: .command)

                    Divider()

                    Button("Run Container…") {
                        model.requestRunContainer()
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(!model.canManageResources)
                }
            }
        }
    }
#else
    import Foundation

    @main
    struct LaunchBayApp {
        static func main() {
            FileHandle.standardError.write(
                Data("LaunchBay is a macOS application.\n".utf8)
            )
        }
    }
#endif
